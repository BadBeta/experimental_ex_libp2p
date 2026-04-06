use libp2p::{Multiaddr, PeerId};
use tokio::sync::oneshot;

/// Commands sent from NIF functions to the swarm event loop task.
pub enum Command {
    // --- Node lifecycle ---
    Dial {
        addr: Multiaddr,
    },
    RegisterEventHandler {
        pid: rustler::LocalPid,
    },
    Shutdown,

    // --- Queries (synchronous via oneshot) ---
    ConnectedPeers {
        reply: oneshot::Sender<Vec<PeerId>>,
    },
    ListeningAddrs {
        reply: oneshot::Sender<Vec<Multiaddr>>,
    },
    BandwidthStats {
        reply: oneshot::Sender<(u64, u64)>,
    },

    // --- GossipSub ---
    Publish {
        topic: String,
        data: Vec<u8>,
    },
    Subscribe {
        topic: String,
    },
    Unsubscribe {
        topic: String,
    },
    GossipsubMeshPeers {
        topic: String,
        reply: oneshot::Sender<Vec<PeerId>>,
    },
    GossipsubAllPeers {
        reply: oneshot::Sender<Vec<PeerId>>,
    },
    GossipsubPeerScore {
        peer_id: PeerId,
        reply: oneshot::Sender<Option<f64>>,
    },

    // --- DHT ---
    DhtPut {
        key: Vec<u8>,
        value: Vec<u8>,
    },
    DhtGet {
        key: Vec<u8>,
    },
    DhtFindPeer {
        peer_id: PeerId,
    },
    DhtProvide {
        key: Vec<u8>,
    },
    DhtFindProviders {
        key: Vec<u8>,
    },
    DhtBootstrap,

    // --- Request-Response RPC ---
    RpcSendRequest {
        peer_id: PeerId,
        data: Vec<u8>,
        reply: oneshot::Sender<String>,
    },
    RpcSendResponse {
        channel_id: String,
        data: Vec<u8>,
    },

    // --- Relay ---
    ListenViaRelay {
        relay_addr: Multiaddr,
    },

    // --- Rendezvous ---
    RendezvousRegister {
        namespace: String,
        ttl: u64,
        rendezvous_peer: PeerId,
    },
    RendezvousDiscover {
        namespace: String,
        rendezvous_peer: PeerId,
    },
    RendezvousUnregister {
        namespace: String,
        rendezvous_peer: PeerId,
    },
}
