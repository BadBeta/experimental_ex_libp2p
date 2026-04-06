//! Composed [`NetworkBehaviour`] for the libp2p node.
//!
//! Includes infrastructure protocols (connection limits, memory limits, identify, ping),
//! application protocols (gossipsub, kademlia, request-response, rendezvous),
//! discovery (mDNS), and NAT traversal (autonat, relay client/server, dcutr, upnp).

use libp2p::{
    autonat, connection_limits, dcutr, gossipsub, identify, kad, mdns,
    memory_connection_limits, ping, relay, rendezvous, request_response,
    swarm::NetworkBehaviour, upnp,
};

/// Composed NetworkBehaviour for the libp2p node.
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

    // Application protocols
    pub gossipsub: gossipsub::Behaviour,
    pub kademlia: kad::Behaviour<kad::store::MemoryStore>,
    pub request_response: request_response::cbor::Behaviour<Vec<u8>, Vec<u8>>,

    // Rendezvous — namespace-based discovery
    pub rendezvous_client: rendezvous::client::Behaviour,
    pub rendezvous_server: rendezvous::server::Behaviour,

    // Discovery
    pub mdns: mdns::tokio::Behaviour,

    // NAT traversal
    pub relay_client: relay::client::Behaviour,
    pub relay_server: relay::Behaviour,
    pub dcutr: dcutr::Behaviour,
    pub autonat: autonat::Behaviour,
    pub upnp: upnp::tokio::Behaviour,
}
