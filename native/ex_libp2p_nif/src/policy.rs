//! Single Source of Truth for tunable production constants.
//!
//! Every retry count, timeout, default scoring parameter, and protocol
//! constant lives here. CLI flags / Elixir config may override at the
//! call site — but the *default* lives only in this file.
//!
//! Litmus: `grep -rn "Duration::from\|f64 = -" src/` should hit only this
//! file plus call sites that read a `policy::*` constant. Inline literals
//! in `node.rs` / `lib.rs` are SSOT violations — file an issue.

/// Default GossipSub `PeerScoreParams` used when the Elixir caller does
/// not supply explicit values. Sourced from the libp2p skill subskill
/// `gossipsub.md` Ethereum beacon chain / Lighthouse production
/// configuration. These values are battle-tested at internet scale.
pub mod gossipsub_default_score {
    /// Penalty for multiple peers per IP / subnet — Sybil mitigation.
    pub const IP_COLOCATION_FACTOR_WEIGHT: f64 = -53.0;
    /// Threshold above which IP colocation penalty applies (3 peers per IP).
    pub const IP_COLOCATION_FACTOR_THRESHOLD: f64 = 3.0;
    /// General misbehaviour penalty weight.
    pub const BEHAVIOUR_PENALTY_WEIGHT: f64 = -15.92;
    /// Per-second decay applied to behaviour penalty.
    pub const BEHAVIOUR_PENALTY_DECAY: f64 = 0.986;
}

/// Maximum entries in the per-node `pending_responses` map for the
/// request-response protocol. A peer flooding inbound requests we don't
/// reply to within the TTL would fill the map without back-pressure;
/// this cap converts that DoS surface into a bounded resource cost.
///
/// At 1024 outstanding inbound requests, a single peer holding all the
/// slots burns ~1 KiB per slot = ~1 MiB of HashMap entries — a documented
/// upper bound, not unlimited growth.
pub const MAX_PENDING_RESPONSES: usize = 1024;

/// Maximum byte size of an imported DHT routing-table snapshot. Files
/// larger than this are rejected before allocation per rust-implementing
/// Rule 20 — prevents a malicious or corrupted state file from causing
/// excess allocation during boot. 4 MiB accommodates very large routing
/// tables (e.g., 10k peers × ~400 bytes per entry); a typical k-bucket
/// fan-out (160 buckets × ~20 entries × ~256 bytes) lands well under
/// 1 MiB. Operators with larger routing tables can override at compile
/// time, but the default protects the boot path.
pub const MAX_DHT_EXPORT_BYTES: usize = 4 * 1024 * 1024;

/// Default GossipSub `PeerScoreThresholds`. Below these scores, the mesh
/// progressively drops gossip / publishes / messages from the offending
/// peer. Sourced from the same Ethereum reference as
/// [`gossipsub_default_score`].
pub mod gossipsub_default_thresholds {
    /// Below this score: stop sending IHAVE/IWANT gossip to the peer.
    pub const GOSSIP: f64 = -4000.0;
    /// Below this score: stop forwarding the peer's publishes.
    pub const PUBLISH: f64 = -8000.0;
    /// Below this score: ignore all messages from the peer.
    pub const GRAYLIST: f64 = -16000.0;
    /// Above this score: accept peer-exchange entries from the peer.
    pub const ACCEPT_PX: f64 = 100.0;
    /// Above this score: opportunistically graft mesh links to the peer.
    pub const OPPORTUNISTIC_GRAFT: f64 = 5.0;
}
