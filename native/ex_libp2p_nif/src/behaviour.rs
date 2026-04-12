//! Composed [`NetworkBehaviour`] for the libp2p node.
//!
//! Includes infrastructure protocols (connection limits, memory limits, identify, ping),
//! application protocols (gossipsub, kademlia, request-response, rendezvous),
//! discovery (mDNS), and NAT traversal (autonat, relay client/server, dcutr, upnp).
//!
//! Optional protocols are wrapped in [`Toggle`] and enabled/disabled via config flags.

use libp2p::{
    autonat, connection_limits, dcutr, gossipsub, identify, kad, mdns,
    memory_connection_limits, ping, relay, rendezvous, request_response,
    swarm::{behaviour::toggle::Toggle, NetworkBehaviour},
    upnp,
};

/// Composed NetworkBehaviour for the libp2p node.
///
/// Infrastructure protocols (connection_limits, memory_limits, identify, ping)
/// and core application protocols (gossipsub, request_response) are always present.
///
/// Optional protocols are wrapped in [`Toggle`] and controlled by `enable_*` config
/// flags. When disabled, they produce no network traffic and consume no resources.
///
/// The relay client is provided by [`SwarmBuilder::with_relay_client`] and
/// passed into the `with_behaviour` closure as the second parameter.
#[derive(NetworkBehaviour)]
pub struct NodeBehaviour {
    // Infrastructure — always present
    pub connection_limits: connection_limits::Behaviour,
    pub memory_limits: memory_connection_limits::Behaviour,
    pub identify: identify::Behaviour,
    pub ping: ping::Behaviour,

    // Application protocols — always present
    pub gossipsub: gossipsub::Behaviour,
    pub request_response: request_response::cbor::Behaviour<Vec<u8>, Vec<u8>>,

    // Optional protocols — controlled by enable_* flags
    pub kademlia: Toggle<kad::Behaviour<kad::store::MemoryStore>>,
    pub mdns: Toggle<mdns::tokio::Behaviour>,
    pub rendezvous_client: Toggle<rendezvous::client::Behaviour>,
    pub rendezvous_server: Toggle<rendezvous::server::Behaviour>,

    // NAT traversal — optional
    pub relay_client: relay::client::Behaviour,
    pub relay_server: Toggle<relay::Behaviour>,
    pub dcutr: Toggle<dcutr::Behaviour>,
    pub autonat: Toggle<autonat::Behaviour>,
    pub upnp: Toggle<upnp::tokio::Behaviour>,
}
