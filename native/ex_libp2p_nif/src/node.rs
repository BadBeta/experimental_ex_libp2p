//! Node lifecycle management — swarm construction, event loop, and shutdown.

use crate::behaviour::{NodeBehaviour, NodeBehaviourEvent};
use crate::commands::Command;
use crate::events::handle_swarm_event;

use futures::{FutureExt, StreamExt};
use libp2p::{
    autonat, connection_limits, dcutr, gossipsub, identify, identity::Keypair, kad, mdns,
    memory_connection_limits, noise, ping, relay, rendezvous, request_response,
    swarm::SwarmEvent, tcp, upnp, yamux, Multiaddr, PeerId, StreamProtocol,
};
use rustler::{LocalPid, ResourceArc};
use std::collections::hash_map::DefaultHasher;
use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::sync::OnceLock;
use std::time::Duration;
use tokio::runtime::Runtime;
use tokio::sync::mpsc;

static RUNTIME: OnceLock<Runtime> = OnceLock::new();

fn get_runtime() -> &'static Runtime {
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .thread_name("libp2p-tokio")
            .build()
            .expect("Failed to create tokio runtime")
    })
}

/// Handle stored in ResourceArc — holds only the command channel sender.
/// Per rust-nif rule 15: hold a channel sender, NOT the Swarm itself.
pub struct NodeHandle {
    pub cmd_tx: mpsc::Sender<Command>,
    pub peer_id: String,
}

#[rustler::resource_impl]
impl rustler::Resource for NodeHandle {}

impl Drop for NodeHandle {
    fn drop(&mut self) {
        // try_send because we're in Drop — can't block, can't async
        let _ = self.cmd_tx.try_send(Command::Shutdown);
    }
}

/// Starts a new libp2p node. Called from the DirtyIo scheduler.
/// Enters the tokio runtime context via block_on because SwarmBuilder,
/// mDNS, and QUIC all require an active tokio reactor.
pub fn start_node_inner(
    config_map: HashMap<String, rustler::Term>,
) -> Result<ResourceArc<NodeHandle>, String> {
    let config = crate::config::NodeConfig::from_map(&config_map)?;
    let runtime = get_runtime();

    // Enter the tokio runtime context — required by SwarmBuilder::with_tokio(),
    // mDNS (netlink sockets), and QUIC (quinn).
    let _guard = runtime.enter();

    let keypair = match &config.keypair_bytes {
        Some(bytes) => {
            Keypair::from_protobuf_encoding(bytes).map_err(|e| format!("invalid keypair: {e}"))?
        }
        None => Keypair::generate_ed25519(),
    };

    let local_peer_id = keypair.public().to_peer_id();
    let peer_id_str = local_peer_id.to_base58();

    // Connection limits
    let limits = connection_limits::ConnectionLimits::default()
        .with_max_pending_incoming(Some(config.max_pending_incoming))
        .with_max_pending_outgoing(Some(config.max_pending_outgoing))
        .with_max_established_incoming(Some(config.max_established_incoming))
        .with_max_established_outgoing(Some(config.max_established_outgoing))
        .with_max_established_per_peer(Some(config.max_established_per_peer));

    // GossipSub
    let message_id_fn = |message: &gossipsub::Message| {
        let mut hasher = DefaultHasher::new();
        message.data.hash(&mut hasher);
        gossipsub::MessageId::from(hasher.finish().to_string())
    };

    let gossipsub_config = gossipsub::ConfigBuilder::default()
        .heartbeat_interval(Duration::from_millis(config.gossipsub_heartbeat_interval_ms))
        .validation_mode(gossipsub::ValidationMode::Strict)
        .message_id_fn(message_id_fn)
        .mesh_n(config.gossipsub_mesh_n)
        .mesh_n_low(config.gossipsub_mesh_n_low)
        .mesh_n_high(config.gossipsub_mesh_n_high)
        .gossip_lazy(config.gossipsub_gossip_lazy)
        .max_transmit_size(config.gossipsub_max_transmit_size)
        .build()
        .map_err(|e| format!("gossipsub config: {e}"))?;

    let gossipsub_behaviour = gossipsub::Behaviour::new(
        gossipsub::MessageAuthenticity::Signed(keypair.clone()),
        gossipsub_config,
    )
    .map_err(|e| format!("gossipsub behaviour: {e}"))?;

    // Kademlia
    let store = kad::store::MemoryStore::new(local_peer_id);
    let kademlia = kad::Behaviour::new(local_peer_id, store);

    // Identify
    let identify_config = identify::Config::new("/ex-libp2p/0.1.0".into(), keypair.public());
    let identify_behaviour = identify::Behaviour::new(identify_config);

    // mDNS
    let mdns_behaviour = mdns::tokio::Behaviour::new(mdns::Config::default(), local_peer_id)
        .map_err(|e| format!("mdns: {e}"))?;

    // Request-Response (CBOR codec, binary payloads)
    let rpc_protocol = StreamProtocol::try_from_owned(config.rpc_protocol_name.clone())
        .map_err(|e| format!("invalid protocol name: {e}"))?;

    let rpc_config = request_response::Config::default()
        .with_request_timeout(Duration::from_secs(config.rpc_request_timeout_secs));

    let request_response_behaviour =
        request_response::cbor::Behaviour::<Vec<u8>, Vec<u8>>::new(
            [(rpc_protocol, request_response::ProtocolSupport::Full)],
            rpc_config,
        );

    let idle_timeout = Duration::from_secs(config.idle_connection_timeout_secs);

    // Relay server config
    let relay_server_config = relay::Config {
        max_reservations: config.relay_max_reservations as usize,
        max_circuits: config.relay_max_circuits as usize,
        max_circuit_duration: Duration::from_secs(config.relay_max_circuit_duration_secs),
        max_circuit_bytes: config.relay_max_circuit_bytes,
        ..Default::default()
    };

    // Memory-based connection limits (reject new connections at 90% system memory)
    let memory_limits = memory_connection_limits::Behaviour::with_max_percentage(0.9);

    // Build the swarm with relay client for NAT traversal.
    // with_relay_client() changes with_behaviour closure to take TWO parameters:
    // |key, relay_client| — the relay_client is provided by the builder.
    let mut swarm = libp2p::SwarmBuilder::with_existing_identity(keypair)
        .with_tokio()
        .with_tcp(
            tcp::Config::default().nodelay(true),
            noise::Config::new,
            yamux::Config::default,
        )
        .map_err(|e| format!("tcp transport: {e}"))?
        .with_quic()
        .with_dns()
        .map_err(|e| format!("dns: {e}"))?
        .with_relay_client(noise::Config::new, yamux::Config::default)
        .map_err(|e| format!("relay client: {e}"))?
        .with_bandwidth_metrics(&mut libp2p::metrics::Registry::default())
        .with_behaviour(|key, relay_client| {
            let local_peer_id = key.public().to_peer_id();

            Ok(NodeBehaviour {
                // Infrastructure
                connection_limits: connection_limits::Behaviour::new(limits),
                memory_limits,
                identify: identify_behaviour,
                ping: ping::Behaviour::default(),

                // Application protocols
                gossipsub: gossipsub_behaviour,
                kademlia,
                request_response: request_response_behaviour,

                // Rendezvous
                rendezvous_client: rendezvous::client::Behaviour::new(key.clone()),
                rendezvous_server: rendezvous::server::Behaviour::new(
                    rendezvous::server::Config::default(),
                ),

                // Discovery
                mdns: mdns_behaviour,

                // NAT traversal
                relay_client,
                relay_server: relay::Behaviour::new(local_peer_id, relay_server_config),
                dcutr: dcutr::Behaviour::new(local_peer_id),
                autonat: autonat::Behaviour::new(local_peer_id, autonat::Config::default()),
                upnp: upnp::tokio::Behaviour::default(),
            })
        })
        .map_err(|e| format!("behaviour: {e}"))?
        .with_swarm_config(|cfg| cfg.with_idle_connection_timeout(idle_timeout))
        .build();

    // Subscribe to configured topics
    for topic_str in &config.gossipsub_topics {
        let topic = gossipsub::IdentTopic::new(topic_str);
        swarm
            .behaviour_mut()
            .gossipsub
            .subscribe(&topic)
            .map_err(|e| format!("subscribe {topic_str}: {e}"))?;
    }

    // Listen on configured addresses
    for addr_str in &config.listen_addrs {
        let addr: Multiaddr = addr_str
            .parse()
            .map_err(|e| format!("invalid listen addr {addr_str}: {e}"))?;
        swarm
            .listen_on(addr)
            .map_err(|e| format!("listen: {e}"))?;
    }

    // FIXED: Use bounded channel for backpressure (was unbounded — OOM risk under load)
    let (cmd_tx, cmd_rx) = mpsc::channel(512);
    let handle_tx = cmd_tx.clone();

    runtime.spawn(async move {
        let result = std::panic::AssertUnwindSafe(swarm_loop(swarm, cmd_rx))
            .catch_unwind()
            .await;

        if let Err(e) = result {
            tracing::error!("swarm loop panicked: {e:?}");
        }
    });

    Ok(ResourceArc::new(NodeHandle {
        cmd_tx: handle_tx,
        peer_id: peer_id_str,
    }))
}

/// The main swarm event loop.
async fn swarm_loop(
    mut swarm: libp2p::Swarm<NodeBehaviour>,
    mut cmd_rx: mpsc::Receiver<Command>,
) {
    let mut event_handler: Option<LocalPid> = None;

    // Pending response channels for request-response protocol.
    // When an inbound request arrives, we store its ResponseChannel here
    // keyed by a unique channel ID. When the Elixir side calls send_response
    // with that channel ID, we retrieve it and send the response.
    let mut pending_responses: HashMap<String, request_response::ResponseChannel<Vec<u8>>> =
        HashMap::new();
    let mut channel_counter: u64 = 0;

    loop {
        tokio::select! {
            cmd = cmd_rx.recv() => {
                match cmd {
                    Some(Command::RegisterEventHandler { pid }) => {
                        event_handler = Some(pid);
                    }
                    Some(Command::Dial { addr }) => {
                        if let Err(e) = swarm.dial(addr.clone()) {
                            tracing::warn!(%addr, %e, "dial failed");
                        }
                    }

                    // ── GossipSub ───────────────────────────────
                    Some(Command::Publish { topic, data }) => {
                        let topic = gossipsub::IdentTopic::new(topic);
                        if let Err(e) = swarm.behaviour_mut().gossipsub.publish(topic, data) {
                            tracing::warn!(%e, "publish failed");
                        }
                    }
                    Some(Command::Subscribe { topic }) => {
                        let topic = gossipsub::IdentTopic::new(topic);
                        if let Err(e) = swarm.behaviour_mut().gossipsub.subscribe(&topic) {
                            tracing::warn!(%e, "subscribe failed");
                        }
                    }
                    Some(Command::Unsubscribe { topic }) => {
                        let topic = gossipsub::IdentTopic::new(topic);
                        if let Err(e) = swarm.behaviour_mut().gossipsub.unsubscribe(&topic) {
                            tracing::warn!(%e, "unsubscribe failed");
                        }
                    }
                    Some(Command::GossipsubMeshPeers { topic, reply }) => {
                        let topic_hash = gossipsub::IdentTopic::new(topic).hash();
                        let peers: Vec<PeerId> = swarm.behaviour()
                            .gossipsub.mesh_peers(&topic_hash)
                            .cloned().collect();
                        let _ = reply.send(peers);
                    }
                    Some(Command::GossipsubAllPeers { reply }) => {
                        let peers: Vec<PeerId> = swarm.behaviour()
                            .gossipsub.all_peers()
                            .map(|(p, _)| *p).collect();
                        let _ = reply.send(peers);
                    }
                    Some(Command::GossipsubPeerScore { peer_id, reply }) => {
                        let score = swarm.behaviour().gossipsub.peer_score(&peer_id);
                        let _ = reply.send(score);
                    }

                    // ── Queries ─────────────────────────────────
                    Some(Command::ConnectedPeers { reply }) => {
                        let peers: Vec<PeerId> = swarm.connected_peers().cloned().collect();
                        let _ = reply.send(peers);
                    }
                    Some(Command::ListeningAddrs { reply }) => {
                        let addrs: Vec<Multiaddr> = swarm.listeners().cloned().collect();
                        let _ = reply.send(addrs);
                    }
                    Some(Command::BandwidthStats { reply }) => {
                        // TODO: wire SwarmBuilder::with_bandwidth_metrics() and read counters
                        let _ = reply.send((0, 0));
                    }

                    // ── DHT ─────────────────────────────────────
                    Some(Command::DhtPut { key, value }) => {
                        let record = kad::Record::new(key, value);
                        if let Err(e) = swarm.behaviour_mut().kademlia.put_record(record, kad::Quorum::One) {
                            tracing::warn!(%e, "dht put failed");
                        }
                    }
                    Some(Command::DhtGet { key }) => {
                        swarm.behaviour_mut().kademlia.get_record(key.into());
                    }
                    Some(Command::DhtFindPeer { peer_id }) => {
                        swarm.behaviour_mut().kademlia.get_closest_peers(peer_id);
                    }
                    Some(Command::DhtProvide { key }) => {
                        if let Err(e) = swarm.behaviour_mut().kademlia.start_providing(key.into()) {
                            tracing::warn!(%e, "dht provide failed");
                        }
                    }
                    Some(Command::DhtFindProviders { key }) => {
                        swarm.behaviour_mut().kademlia.get_providers(key.into());
                    }
                    Some(Command::DhtBootstrap) => {
                        if let Err(e) = swarm.behaviour_mut().kademlia.bootstrap() {
                            tracing::warn!(%e, "dht bootstrap failed");
                        }
                    }

                    // ── Request-Response ────────────────────────
                    Some(Command::RpcSendRequest { peer_id, data, reply }) => {
                        let req_id = swarm.behaviour_mut().request_response
                            .send_request(&peer_id, data);
                        let _ = reply.send(format!("{req_id:?}"));
                    }
                    Some(Command::RpcSendResponse { channel_id, data }) => {
                        match pending_responses.remove(&channel_id) {
                            Some(channel) => {
                                if let Err(resp) = swarm.behaviour_mut()
                                    .request_response.send_response(channel, data)
                                {
                                    tracing::warn!(
                                        %channel_id,
                                        resp_len = resp.len(),
                                        "send_response failed: channel closed"
                                    );
                                }
                            }
                            None => {
                                tracing::warn!(
                                    %channel_id,
                                    "send_response: unknown channel ID (expired or already used)"
                                );
                            }
                        }
                    }

                    // ── Relay ───────────────────────────────────
                    Some(Command::ListenViaRelay { relay_addr }) => {
                        if let Err(e) = swarm.listen_on(relay_addr.clone()) {
                            tracing::warn!(%relay_addr, %e, "listen via relay failed");
                        }
                    }

                    // ── Rendezvous ─────────────────────────────
                    Some(Command::RendezvousRegister { namespace, ttl, rendezvous_peer }) => {
                        let ns = match rendezvous::Namespace::new(namespace.clone()) {
                            Ok(ns) => ns,
                            Err(e) => {
                                tracing::warn!(%namespace, %e, "invalid rendezvous namespace");
                                continue;
                            }
                        };
                        if let Err(e) = swarm.behaviour_mut().rendezvous_client.register(
                            ns,
                            rendezvous_peer,
                            Some(ttl),
                        ) {
                            tracing::warn!(%namespace, %e, "rendezvous register failed");
                        }
                    }
                    Some(Command::RendezvousDiscover { namespace, rendezvous_peer }) => {
                        let ns = rendezvous::Namespace::new(namespace.clone()).ok();
                        swarm.behaviour_mut().rendezvous_client.discover(
                            ns,
                            None, // cookie — None for first discovery
                            None, // limit
                            rendezvous_peer,
                        );
                    }
                    Some(Command::RendezvousUnregister { namespace, rendezvous_peer }) => {
                        let ns = match rendezvous::Namespace::new(namespace.clone()) {
                            Ok(ns) => ns,
                            Err(e) => {
                                tracing::warn!(%namespace, %e, "invalid rendezvous namespace");
                                continue;
                            }
                        };
                        swarm.behaviour_mut().rendezvous_client.unregister(
                            ns,
                            rendezvous_peer,
                        );
                    }

                    Some(Command::Shutdown) | None => break,
                }
            }

            event = swarm.select_next_some() => {
                // Request-response inbound requests need special handling:
                // we extract the ResponseChannel (which is !Clone) before
                // encoding the event for Elixir. The channel is stored in
                // pending_responses keyed by a unique channel ID.
                match event {
                    SwarmEvent::Behaviour(NodeBehaviourEvent::RequestResponse(
                        request_response::Event::Message {
                            peer,
                            message: request_response::Message::Request {
                                request_id,
                                request,
                                channel,
                            },
                        },
                    )) => {
                        channel_counter += 1;
                        let channel_id = format!("ch-{channel_counter}");
                        pending_responses.insert(channel_id.clone(), channel);

                        if let Some(ref pid) = event_handler {
                            crate::events::send_inbound_request(
                                pid,
                                &peer,
                                &format!("{request_id:?}"),
                                &channel_id,
                                &request,
                            );
                        }
                    }
                    SwarmEvent::Behaviour(NodeBehaviourEvent::RequestResponse(
                        request_response::Event::Message {
                            peer,
                            message: request_response::Message::Response {
                                request_id,
                                response,
                            },
                        },
                    )) => {
                        if let Some(ref pid) = event_handler {
                            crate::events::send_outbound_response(
                                pid,
                                &peer,
                                &format!("{request_id:?}"),
                                &response,
                            );
                        }
                    }
                    // All other events go through the generic handler
                    other => {
                        if let Some(ref pid) = event_handler {
                            handle_swarm_event(other, pid);
                        }
                    }
                }
            }
        }
    }

    tracing::info!("swarm loop exited");
}
