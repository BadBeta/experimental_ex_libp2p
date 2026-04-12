/// Configuration received from the Elixir side as a map.
/// All fields are read by [`crate::node::start_node_inner`].
/// Fields for behaviours not yet wired (relay, autonat, etc.) are parsed
/// and stored for when those behaviours are added to [`NodeBehaviour`].
#[allow(dead_code)]
pub struct NodeConfig {
    pub keypair_bytes: Option<Vec<u8>>,
    pub listen_addrs: Vec<String>,
    pub bootstrap_peers: Vec<String>,
    // GossipSub
    pub gossipsub_topics: Vec<String>,
    pub gossipsub_mesh_n: usize,
    pub gossipsub_mesh_n_low: usize,
    pub gossipsub_mesh_n_high: usize,
    pub gossipsub_gossip_lazy: usize,
    pub gossipsub_max_transmit_size: usize,
    pub gossipsub_heartbeat_interval_ms: u64,
    // Protocol enables
    pub enable_mdns: bool,
    pub enable_kademlia: bool,
    pub enable_relay: bool,
    pub enable_relay_server: bool,
    pub enable_autonat: bool,
    pub enable_upnp: bool,
    pub enable_websocket: bool,
    pub enable_rendezvous_client: bool,
    pub enable_rendezvous_server: bool,
    // Request-Response
    pub rpc_protocol_name: String,
    pub rpc_request_timeout_secs: u64,
    // Connection limits
    pub idle_connection_timeout_secs: u64,
    pub max_established_incoming: u32,
    pub max_established_outgoing: u32,
    pub max_pending_incoming: u32,
    pub max_pending_outgoing: u32,
    pub max_established_per_peer: u32,
    // Relay server config
    pub relay_max_reservations: u32,
    pub relay_max_circuits: u32,
    pub relay_max_circuit_duration_secs: u64,
    pub relay_max_circuit_bytes: u64,
    // Peer scoring (parsed from nested Elixir maps)
    pub peer_score: Option<PeerScoreConfig>,
    pub thresholds: Option<ThresholdsConfig>,
}

/// GossipSub peer scoring parameters (maps to libp2p::gossipsub::PeerScoreParams).
#[allow(dead_code)]
pub struct PeerScoreConfig {
    pub ip_colocation_factor_weight: f64,
    pub ip_colocation_factor_threshold: f64,
    pub behaviour_penalty_weight: f64,
    pub behaviour_penalty_decay: f64,
}

/// GossipSub score thresholds (maps to libp2p::gossipsub::PeerScoreThresholds).
#[allow(dead_code)]
pub struct ThresholdsConfig {
    pub gossip_threshold: f64,
    pub publish_threshold: f64,
    pub graylist_threshold: f64,
    pub accept_px_threshold: f64,
    pub opportunistic_graft_threshold: f64,
}

impl NodeConfig {
    pub fn from_map<'a>(
        map: &std::collections::HashMap<String, rustler::Term<'a>>,
    ) -> Result<Self, String> {
        Ok(Self {
            keypair_bytes: get_binary(map, "keypair_bytes"),
            listen_addrs: get_string_list(map, "listen_addrs")?,
            bootstrap_peers: get_string_list(map, "bootstrap_peers")?,
            gossipsub_topics: get_string_list(map, "gossipsub_topics")?,
            gossipsub_mesh_n: get_usize(map, "gossipsub_mesh_n", 6),
            gossipsub_mesh_n_low: get_usize(map, "gossipsub_mesh_n_low", 4),
            gossipsub_mesh_n_high: get_usize(map, "gossipsub_mesh_n_high", 12),
            gossipsub_gossip_lazy: get_usize(map, "gossipsub_gossip_lazy", 6),
            gossipsub_max_transmit_size: get_usize(map, "gossipsub_max_transmit_size", 65536),
            gossipsub_heartbeat_interval_ms: get_u64(map, "gossipsub_heartbeat_interval_ms", 1000),
            enable_mdns: get_bool(map, "enable_mdns", true),
            enable_kademlia: get_bool(map, "enable_kademlia", true),
            enable_relay: get_bool(map, "enable_relay", false),
            enable_relay_server: get_bool(map, "enable_relay_server", false),
            enable_autonat: get_bool(map, "enable_autonat", false),
            enable_upnp: get_bool(map, "enable_upnp", false),
            enable_websocket: get_bool(map, "enable_websocket", false),
            enable_rendezvous_client: get_bool(map, "enable_rendezvous_client", false),
            enable_rendezvous_server: get_bool(map, "enable_rendezvous_server", false),
            rpc_protocol_name: get_string(map, "rpc_protocol_name", "/ex-libp2p/rpc/1.0.0"),
            rpc_request_timeout_secs: get_u64(map, "rpc_request_timeout_secs", 30),
            idle_connection_timeout_secs: get_u64(map, "idle_connection_timeout_secs", 60),
            max_established_incoming: get_u32(map, "max_established_incoming", 256),
            max_established_outgoing: get_u32(map, "max_established_outgoing", 256),
            max_pending_incoming: get_u32(map, "max_pending_incoming", 128),
            max_pending_outgoing: get_u32(map, "max_pending_outgoing", 64),
            max_established_per_peer: get_u32(map, "max_established_per_peer", 2),
            relay_max_reservations: get_u32(map, "relay_max_reservations", 128),
            relay_max_circuits: get_u32(map, "relay_max_circuits", 16),
            relay_max_circuit_duration_secs: get_u64(map, "relay_max_circuit_duration_secs", 120),
            relay_max_circuit_bytes: get_u64(map, "relay_max_circuit_bytes", 131072),
            peer_score: get_peer_score(map),
            thresholds: get_thresholds(map),
        })
    }
}

fn get_string_list(
    map: &std::collections::HashMap<String, rustler::Term>,
    key: &str,
) -> Result<Vec<String>, String> {
    match map.get(key) {
        Some(term) => term.decode().map_err(|_| format!("invalid {key}")),
        None => Ok(Vec::new()),
    }
}

fn get_string(
    map: &std::collections::HashMap<String, rustler::Term>,
    key: &str,
    default: &str,
) -> String {
    map.get(key)
        .and_then(|t| t.decode::<String>().ok())
        .unwrap_or_else(|| default.to_string())
}

fn get_binary(
    map: &std::collections::HashMap<String, rustler::Term>,
    key: &str,
) -> Option<Vec<u8>> {
    map.get(key).and_then(|t| {
        // Try decoding as Binary first (Elixir binary), fall back to nil check
        if t.is_atom() {
            // nil atom → None
            return None;
        }
        t.decode::<rustler::Binary>()
            .ok()
            .map(|b| b.as_slice().to_vec())
    })
}

fn get_bool(
    map: &std::collections::HashMap<String, rustler::Term>,
    key: &str,
    default: bool,
) -> bool {
    map.get(key)
        .and_then(|t| t.decode::<bool>().ok())
        .unwrap_or(default)
}

fn get_u64(
    map: &std::collections::HashMap<String, rustler::Term>,
    key: &str,
    default: u64,
) -> u64 {
    map.get(key)
        .and_then(|t| t.decode::<u64>().ok())
        .unwrap_or(default)
}

fn get_u32(
    map: &std::collections::HashMap<String, rustler::Term>,
    key: &str,
    default: u32,
) -> u32 {
    map.get(key)
        .and_then(|t| t.decode::<u32>().ok())
        .unwrap_or(default)
}

fn get_usize(
    map: &std::collections::HashMap<String, rustler::Term>,
    key: &str,
    default: usize,
) -> usize {
    map.get(key)
        .and_then(|t| t.decode::<u64>().ok())
        .map(|v| v as usize)
        .unwrap_or(default)
}

fn get_f64(
    map: &std::collections::HashMap<String, rustler::Term>,
    key: &str,
    default: f64,
) -> f64 {
    map.get(key)
        .and_then(|t| t.decode::<f64>().ok())
        .unwrap_or(default)
}

fn get_peer_score<'a>(
    map: &std::collections::HashMap<String, rustler::Term<'a>>,
) -> Option<PeerScoreConfig> {
    let term = map.get("gossipsub_peer_score")?;
    if term.is_atom() { return None; }
    let inner: std::collections::HashMap<String, rustler::Term> = term.decode().ok()?;
    Some(PeerScoreConfig {
        ip_colocation_factor_weight: get_f64(&inner, "ip_colocation_factor_weight", -53.0),
        ip_colocation_factor_threshold: get_f64(&inner, "ip_colocation_factor_threshold", 3.0),
        behaviour_penalty_weight: get_f64(&inner, "behaviour_penalty_weight", -15.92),
        behaviour_penalty_decay: get_f64(&inner, "behaviour_penalty_decay", 0.986),
    })
}

fn get_thresholds<'a>(
    map: &std::collections::HashMap<String, rustler::Term<'a>>,
) -> Option<ThresholdsConfig> {
    let term = map.get("gossipsub_thresholds")?;
    if term.is_atom() { return None; }
    let inner: std::collections::HashMap<String, rustler::Term> = term.decode().ok()?;
    Some(ThresholdsConfig {
        gossip_threshold: get_f64(&inner, "gossip_threshold", -4000.0),
        publish_threshold: get_f64(&inner, "publish_threshold", -8000.0),
        graylist_threshold: get_f64(&inner, "graylist_threshold", -16000.0),
        accept_px_threshold: get_f64(&inner, "accept_px_threshold", 100.0),
        opportunistic_graft_threshold: get_f64(&inner, "opportunistic_graft_threshold", 5.0),
    })
}
