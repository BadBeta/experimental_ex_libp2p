//! SwarmEvent to Elixir term translation.
//!
//! Converts libp2p events into `{:libp2p_event, {type, ...}}` tuples
//! sent to the registered GenServer PID via [`OwnedEnv::send_and_clear`].

use crate::atoms;
use crate::behaviour::NodeBehaviourEvent;
use libp2p::swarm::SwarmEvent;
use libp2p::PeerId;
use rustler::{Encoder, Env, LocalPid, OwnedEnv, Term};

/// Translates SwarmEvents into Elixir terms and sends them to the registered PID.
/// NOTE: request_response Message events are handled directly in the swarm loop
/// because we need to extract the ResponseChannel before encoding.
pub fn handle_swarm_event(event: SwarmEvent<NodeBehaviourEvent>, pid: &LocalPid) {
    let pid = pid.clone();
    let mut owned_env = OwnedEnv::new();

    let _ = owned_env.send_and_clear(&pid, |env| match event {
        SwarmEvent::ConnectionEstablished {
            peer_id,
            num_established,
            endpoint,
            ..
        } => {
            let endpoint_atom = if endpoint.is_dialer() {
                atoms::dialer().encode(env)
            } else {
                atoms::listener().encode(env)
            };
            (
                atoms::libp2p_event(),
                (
                    atoms::connection_established(),
                    peer_id.to_base58(),
                    num_established.get(),
                    endpoint_atom,
                ),
            )
                .encode(env)
        }

        SwarmEvent::ConnectionClosed {
            peer_id,
            num_established,
            cause,
            ..
        } => {
            let cause_str = cause
                .map(|c| format!("{c:?}"))
                .unwrap_or_else(|| "unknown".to_string());
            (
                atoms::libp2p_event(),
                (
                    atoms::connection_closed(),
                    peer_id.to_base58(),
                    num_established,
                    cause_str,
                ),
            )
                .encode(env)
        }

        SwarmEvent::NewListenAddr {
            address,
            listener_id,
            ..
        } => (
            atoms::libp2p_event(),
            (
                atoms::new_listen_addr(),
                address.to_string(),
                format!("{listener_id:?}"),
            ),
        )
            .encode(env),

        SwarmEvent::ExternalAddrConfirmed { address } => (
            atoms::libp2p_event(),
            (atoms::external_addr_confirmed(), address.to_string()),
        )
            .encode(env),

        SwarmEvent::OutgoingConnectionError { peer_id, error, .. } => {
            let peer_str: Option<String> = peer_id.map(|p| p.to_base58());
            (
                atoms::libp2p_event(),
                (
                    atoms::dial_failure(),
                    peer_str,
                    format!("{error:?}"),
                ),
            )
                .encode(env)
        }

        // GossipSub
        SwarmEvent::Behaviour(NodeBehaviourEvent::Gossipsub(
            libp2p::gossipsub::Event::Message {
                propagation_source: _,
                message_id,
                message,
            },
        )) => {
            let source = message.source.map(|p| p.to_base58());
            let data = encode_binary(env, &message.data);
            (
                atoms::libp2p_event(),
                (
                    atoms::gossipsub_message(),
                    message.topic.to_string(),
                    data,
                    source,
                    message_id.to_string(),
                ),
            )
                .encode(env)
        }

        // mDNS
        SwarmEvent::Behaviour(NodeBehaviourEvent::Mdns(libp2p::mdns::Event::Discovered(
            peers,
        ))) => {
            let mut result: Term = atoms::libp2p_noop().encode(env);
            for (peer_id, addr) in peers {
                result = (
                    atoms::libp2p_event(),
                    (
                        atoms::peer_discovered(),
                        peer_id.to_base58(),
                        vec![addr.to_string()],
                    ),
                )
                    .encode(env);
            }
            result
        }

        // Kademlia
        SwarmEvent::Behaviour(NodeBehaviourEvent::Kademlia(event)) => {
            encode_kad_event(env, event)
        }

        // Request-response failure events (success events handled in swarm_loop)
        SwarmEvent::Behaviour(NodeBehaviourEvent::RequestResponse(
            libp2p::request_response::Event::OutboundFailure {
                peer, request_id, error,
            },
        )) => (
            atoms::libp2p_event(),
            (
                atoms::dial_failure(),
                Some(peer.to_base58()),
                format!("rpc outbound failure {request_id:?}: {error:?}"),
            ),
        )
            .encode(env),

        SwarmEvent::Behaviour(NodeBehaviourEvent::RequestResponse(
            libp2p::request_response::Event::InboundFailure {
                peer, request_id, error,
            },
        )) => (
            atoms::libp2p_event(),
            (
                atoms::dial_failure(),
                Some(peer.to_base58()),
                format!("rpc inbound failure {request_id:?}: {error:?}"),
            ),
        )
            .encode(env),

        // AutoNAT — NAT status detection
        SwarmEvent::Behaviour(NodeBehaviourEvent::Autonat(
            libp2p::autonat::Event::StatusChanged { old: _, new },
        )) => {
            let (status_atom, addr) = match new {
                libp2p::autonat::NatStatus::Public(addr) => {
                    (atoms::public(), Some(addr.to_string()))
                }
                libp2p::autonat::NatStatus::Private => (atoms::private(), None),
                libp2p::autonat::NatStatus::Unknown => (atoms::unknown(), None),
            };
            (
                atoms::libp2p_event(),
                (atoms::nat_status_changed(), status_atom, addr),
            )
                .encode(env)
        }

        // DCUtR — hole punch outcome (Event is a struct, not an enum)
        SwarmEvent::Behaviour(NodeBehaviourEvent::Dcutr(event)) => {
            let result_term = match event.result {
                Ok(_) => atoms::success().encode(env),
                Err(ref e) => (atoms::failure(), format!("{e:?}")).encode(env),
            };
            (
                atoms::libp2p_event(),
                (
                    atoms::hole_punch_outcome(),
                    event.remote_peer_id.to_base58(),
                    result_term,
                ),
            )
                .encode(env)
        }

        // Relay client — reservation accepted
        SwarmEvent::Behaviour(NodeBehaviourEvent::RelayClient(
            libp2p::relay::client::Event::ReservationReqAccepted {
                relay_peer_id, ..
            },
        )) => (
            atoms::libp2p_event(),
            (
                atoms::relay_reservation_accepted(),
                relay_peer_id.to_base58(),
                "", // relay addr filled by the listener
            ),
        )
            .encode(env),

        // UPnP — port mapping events are informational, log them
        SwarmEvent::Behaviour(NodeBehaviourEvent::Upnp(
            libp2p::upnp::Event::NewExternalAddr(addr),
        )) => (
            atoms::libp2p_event(),
            (atoms::external_addr_confirmed(), addr.to_string()),
        )
            .encode(env),

        // Rendezvous client — discovered peers
        SwarmEvent::Behaviour(NodeBehaviourEvent::RendezvousClient(
            libp2p::rendezvous::client::Event::Discovered {
                registrations,
                ..
            },
        )) => {
            // Send one peer_discovered event per registration
            let mut result: Term = atoms::libp2p_noop().encode(env);
            for registration in registrations {
                let addrs: Vec<String> = registration.record.addresses().iter()
                    .map(|a| a.to_string()).collect();
                result = (
                    atoms::libp2p_event(),
                    (
                        atoms::peer_discovered(),
                        registration.record.peer_id().to_base58(),
                        addrs,
                    ),
                )
                    .encode(env);
            }
            result
        }

        _ => atoms::libp2p_noop().encode(env),
    });
}

/// Send an inbound request event to Elixir.
/// Called from the swarm loop after extracting the ResponseChannel.
pub fn send_inbound_request(
    pid: &LocalPid,
    peer: &PeerId,
    request_id: &str,
    channel_id: &str,
    data: &[u8],
) {
    let pid = pid.clone();
    let peer_str = peer.to_base58();
    let req_id = request_id.to_string();
    let ch_id = channel_id.to_string();
    let data = data.to_vec();

    let mut owned_env = OwnedEnv::new();
    let _ = owned_env.send_and_clear(&pid, |env| {
        (
            atoms::libp2p_event(),
            (
                atoms::inbound_request(),
                req_id.as_str(),
                ch_id.as_str(),
                peer_str.as_str(),
                encode_binary(env, &data),
            ),
        )
            .encode(env)
    });
}

/// Send an outbound response event to Elixir.
/// Called from the swarm loop for response messages.
pub fn send_outbound_response(
    pid: &LocalPid,
    peer: &PeerId,
    request_id: &str,
    data: &[u8],
) {
    let pid = pid.clone();
    let peer_str = peer.to_base58();
    let req_id = request_id.to_string();
    let data = data.to_vec();

    let mut owned_env = OwnedEnv::new();
    let _ = owned_env.send_and_clear(&pid, |env| {
        (
            atoms::libp2p_event(),
            (
                atoms::outbound_response(),
                req_id.as_str(),
                peer_str.as_str(),
                encode_binary(env, &data),
            ),
        )
            .encode(env)
    });
}

fn encode_kad_event(env: Env, event: libp2p::kad::Event) -> Term {
    match event {
        libp2p::kad::Event::OutboundQueryProgressed { result, id, .. } => match result {
            libp2p::kad::QueryResult::GetRecord(Ok(
                libp2p::kad::GetRecordOk::FoundRecord(libp2p::kad::PeerRecord { record, .. }),
            )) => (
                atoms::libp2p_event(),
                (
                    atoms::dht_query_result(),
                    format!("{id:?}"),
                    (
                        atoms::found_record(),
                        encode_binary(env, record.key.as_ref()),
                        encode_binary(env, &record.value),
                    ),
                ),
            )
                .encode(env),

            libp2p::kad::QueryResult::GetRecord(Err(_)) => (
                atoms::libp2p_event(),
                (
                    atoms::dht_query_result(),
                    format!("{id:?}"),
                    atoms::not_found(),
                ),
            )
                .encode(env),

            libp2p::kad::QueryResult::PutRecord(Ok(ok)) => (
                atoms::libp2p_event(),
                (
                    atoms::dht_query_result(),
                    format!("{id:?}"),
                    (atoms::put_record_ok(), format!("{:?}", ok.key)),
                ),
            )
                .encode(env),

            libp2p::kad::QueryResult::GetProviders(Ok(ok)) => {
                if let libp2p::kad::GetProvidersOk::FoundProviders { providers, .. } = ok {
                    let provider_strs: Vec<String> =
                        providers.into_iter().map(|p| p.to_base58()).collect();
                    (
                        atoms::libp2p_event(),
                        (
                            atoms::dht_query_result(),
                            format!("{id:?}"),
                            (atoms::found_providers(), provider_strs),
                        ),
                    )
                        .encode(env)
                } else {
                    atoms::libp2p_noop().encode(env)
                }
            }

            libp2p::kad::QueryResult::Bootstrap(Ok(ok)) => (
                atoms::libp2p_event(),
                (
                    atoms::dht_query_result(),
                    format!("{id:?}"),
                    (atoms::bootstrap_ok(), ok.num_remaining),
                ),
            )
                .encode(env),

            _ => atoms::libp2p_noop().encode(env),
        },
        _ => atoms::libp2p_noop().encode(env),
    }
}

fn encode_binary<'a>(env: Env<'a>, data: &[u8]) -> Term<'a> {
    let mut bin = rustler::OwnedBinary::new(data.len()).expect("binary allocation");
    bin.as_mut_slice().copy_from_slice(data);
    bin.release(env).encode(env)
}
