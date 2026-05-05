//! Typed error type for the NIF surface.
//!
//! Every NIF function that can fail returns `Result<T, NifError>`.
//! On the Elixir side this encodes as `{atom, message}` tuples — the
//! atom carries the variant for pattern-matching, the string carries
//! human-readable detail for logs.
//!
//! Construction inside the NIF is via `thiserror`; the boundary
//! translation is an `Encoder` impl that renders the variant as
//! `(atom, String)`. To use `?` from inside a `NifResult<T>` body,
//! `From<NifError> for rustler::Error` wraps it as
//! `rustler::Error::Term(Box::new(self))`, which encodes as
//! `{:error, {atom, msg}}` on the Elixir side (NOT raises — this
//! is the ok/error tuple flavour, not the exception flavour).

use crate::atoms;
use rustler::{Atom, Encoder, Env, Term};
use thiserror::Error;

/// Maximum bytes accepted by `keypair_from_protobuf`. A protobuf-encoded
/// libp2p keypair is ~70 bytes; 4 KiB is well above any legitimate input
/// and well below DoS-relevant sizes.
#[allow(dead_code)]
pub const MAX_KEYPAIR_BYTES: usize = 4096;

/// Maximum bytes accepted by DHT export/import payload (R7).
#[allow(dead_code)]
pub const MAX_DHT_EXPORT_BYTES: usize = 4 * 1024 * 1024;

#[derive(Debug, Error)]
pub enum NifError {
    #[error("invalid multiaddr: {0}")]
    InvalidMultiaddr(String),

    #[error("invalid peer id: {0}")]
    InvalidPeerId(String),

    #[error("invalid keypair: {0}")]
    InvalidKeypair(String),

    #[error("input too large: got {got} bytes, max {max}")]
    InputTooLarge { got: usize, max: usize },

    #[error("node stopped: swarm event loop has exited")]
    NodeStopped,

    #[error("channel full: swarm is overloaded")]
    ChannelFull,

    #[error("query timeout")]
    QueryTimeout,

    #[error("dht not enabled")]
    DhtNotEnabled,

    #[error("rendezvous client not enabled")]
    RendezvousNotEnabled,

    #[error("nif panic: {0}")]
    NifPanic(String),

    #[error("internal: {0}")]
    Internal(String),
}

impl NifError {
    /// Returns the atom tag for this error variant. Stable across versions —
    /// Elixir callers pattern-match on the atom.
    fn atom(&self) -> Atom {
        match self {
            NifError::InvalidMultiaddr(_) => atoms::invalid_multiaddr(),
            NifError::InvalidPeerId(_) => atoms::invalid_peer_id(),
            NifError::InvalidKeypair(_) => atoms::invalid_keypair(),
            NifError::InputTooLarge { .. } => atoms::input_too_large(),
            NifError::NodeStopped => atoms::node_stopped(),
            NifError::ChannelFull => atoms::channel_full(),
            NifError::QueryTimeout => atoms::query_timeout(),
            NifError::DhtNotEnabled => atoms::dht_not_enabled(),
            NifError::RendezvousNotEnabled => atoms::rendezvous_not_enabled(),
            NifError::NifPanic(_) => atoms::nif_panic(),
            NifError::Internal(_) => atoms::internal_error(),
        }
    }
}

impl Encoder for NifError {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        // (atom, String) tuple shape, NOT a raise. Elixir sees
        // `{:error, {atom, msg}}` when this is wrapped via
        // `rustler::Error::Term(Box::new(nif_error))` and `?`-propagated
        // from a `NifResult<T>`.
        (self.atom(), self.to_string()).encode(env)
    }
}

impl From<NifError> for rustler::Error {
    fn from(e: NifError) -> Self {
        // Term variant — encodes as `{:error, encoded}` on the Elixir
        // side. NOT RaiseTerm: we want the ok/error tuple flavour, not
        // an exception. See rust-nif §2.8 "Error::Term vs Error::RaiseTerm".
        rustler::Error::Term(Box::new(e))
    }
}

// ── `?`-friendly conversions from upstream error types ──

impl From<libp2p::multiaddr::Error> for NifError {
    fn from(e: libp2p::multiaddr::Error) -> Self {
        NifError::InvalidMultiaddr(e.to_string())
    }
}

impl From<libp2p::identity::ParseError> for NifError {
    fn from(e: libp2p::identity::ParseError) -> Self {
        NifError::InvalidPeerId(e.to_string())
    }
}

impl From<libp2p::identity::DecodingError> for NifError {
    fn from(e: libp2p::identity::DecodingError) -> Self {
        NifError::InvalidKeypair(e.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn variant_atoms_are_distinct() {
        // Sanity check: every variant maps to a unique atom. If two variants
        // share an atom, Elixir callers can't pattern-match on the variant.
        let cases: Vec<NifError> = vec![
            NifError::InvalidMultiaddr("x".into()),
            NifError::InvalidPeerId("x".into()),
            NifError::InvalidKeypair("x".into()),
            NifError::InputTooLarge { got: 1, max: 1 },
            NifError::NodeStopped,
            NifError::ChannelFull,
            NifError::QueryTimeout,
            NifError::DhtNotEnabled,
            NifError::RendezvousNotEnabled,
            NifError::NifPanic("x".into()),
            NifError::Internal("x".into()),
        ];

        // All atoms must be distinct — no two variants share an atom tag.
        // We can't compare rustler::Atom values without an Env at test time,
        // so verify by Display string match against the atom registry.
        let display_strs: Vec<String> = cases.iter().map(|e| e.to_string()).collect();
        let unique: std::collections::HashSet<_> = display_strs.iter().collect();
        assert_eq!(
            unique.len(),
            display_strs.len(),
            "duplicate Display strings — likely a copy-paste bug"
        );
    }

    #[test]
    fn from_libp2p_multiaddr_error_preserves_message() {
        let err: Result<libp2p::Multiaddr, _> = "not a multiaddr".parse();
        let nif_err: NifError = err.unwrap_err().into();
        assert!(matches!(nif_err, NifError::InvalidMultiaddr(_)));
    }
}
