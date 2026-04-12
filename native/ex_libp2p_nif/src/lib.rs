//! ExLibp2p NIF — Rust NIF bindings for rust-libp2p.
//!
//! Provides the native interface between Elixir and the libp2p networking stack.
//! Each NIF function sends a [`Command`] through an mpsc channel to the swarm
//! event loop task, which runs on a dedicated tokio runtime.
//!
//! Fire-and-forget operations (dial, publish, subscribe) return `:ok` immediately.
//! Query operations (connected_peers, mesh_peers) use oneshot channels and block
//! on dirty schedulers.

mod atoms;
mod behaviour;
mod commands;
mod config;
mod events;
mod node;

use commands::Command;
use node::NodeHandle;
use rustler::{Binary, Encoder, LocalPid, ResourceArc, Term};
use std::collections::HashMap;
use tokio::sync::oneshot;

// ── Node lifecycle ──────────────────────────────────────────────

#[rustler::nif(schedule = "DirtyIo")]
fn start_node(
    config: HashMap<String, Term>,
) -> Result<ResourceArc<NodeHandle>, (rustler::Atom, String)> {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        node::start_node_inner(config)
    })) {
        Ok(Ok(handle)) => Ok(handle),
        Ok(Err(e)) => Err((atoms::error(), e)),
        Err(_) => Err((
            atoms::error(),
            "NIF panic caught in start_node — check Rust logs".to_string(),
        )),
    }
}

#[rustler::nif]
fn stop_node(handle: ResourceArc<NodeHandle>) -> rustler::Atom {
    let _ = handle.cmd_tx.send(Command::Shutdown);
    atoms::ok()
}

#[rustler::nif]
fn register_event_handler(handle: ResourceArc<NodeHandle>, pid: LocalPid) -> rustler::Atom {
    let _ = handle.cmd_tx.send(Command::RegisterEventHandler { pid });
    atoms::ok()
}

#[rustler::nif]
fn get_peer_id(handle: ResourceArc<NodeHandle>) -> String {
    handle.peer_id.clone()
}

// ── Synchronous queries ─────────────────────────────────────────

/// Returns the list or an empty list if the node is stopped.
/// The Elixir GenServer wraps the result in {:ok, _}.
#[rustler::nif(schedule = "DirtyCpu")]
fn connected_peers(handle: ResourceArc<NodeHandle>) -> Vec<String> {
    query(&handle, |tx| Command::ConnectedPeers { reply: tx })
        .map(peer_ids_to_strings)
        .unwrap_or_default()
}

#[rustler::nif(schedule = "DirtyCpu")]
fn listening_addrs(handle: ResourceArc<NodeHandle>) -> Vec<String> {
    query(&handle, |tx| Command::ListeningAddrs { reply: tx })
        .map(|addrs| addrs.into_iter().map(|a| a.to_string()).collect())
        .unwrap_or_default()
}

#[rustler::nif(schedule = "DirtyCpu")]
fn bandwidth_stats(handle: ResourceArc<NodeHandle>) -> (rustler::Atom, u64, u64) {
    match query(&handle, |tx| Command::BandwidthStats { reply: tx }) {
        Some((bytes_in, bytes_out)) => (atoms::ok(), bytes_in, bytes_out),
        None => (atoms::error(), 0, 0),
    }
}

/// Sends a query command with a oneshot reply channel and blocks for the response.
/// Returns `None` if the node is stopped or the channel is full/dropped.
/// MUST be called from a DirtyCpu/DirtyIo scheduler — blocking_recv blocks the thread.
fn query<T>(
    handle: &ResourceArc<NodeHandle>,
    make_cmd: impl FnOnce(oneshot::Sender<T>) -> Command,
) -> Option<T> {
    let (tx, rx) = oneshot::channel();
    handle.cmd_tx.try_send(make_cmd(tx)).ok()?;
    rx.blocking_recv().ok()
}

fn peer_ids_to_strings(peers: Vec<libp2p::PeerId>) -> Vec<String> {
    peers.into_iter().map(|p| p.to_base58()).collect()
}

// ── Fire-and-forget commands ────────────────────────────────────
// Return :ok | {:error, "reason"} — using Result<bool, String> per rust-nif
// rule 2 to avoid {:ok, :ok} double-wrapping. Elixir sees {:ok, true} on
// success and {:error, "node_stopped"} or {:error, "channel_full"} on failure.

#[rustler::nif]
fn dial(handle: ResourceArc<NodeHandle>, addr: String) -> Result<bool, String> {
    let multiaddr = addr
        .parse::<libp2p::Multiaddr>()
        .map_err(|e| format!("invalid multiaddr: {e}"))?;
    send_cmd(&handle, Command::Dial { addr: multiaddr })?;
    Ok(true)
}

#[rustler::nif]
fn publish(handle: ResourceArc<NodeHandle>, topic: String, data: Binary) -> Result<bool, String> {
    let bytes = data.as_slice().to_vec();
    send_cmd(&handle, Command::Publish { topic, data: bytes })?;
    Ok(true)
}

#[rustler::nif]
fn subscribe(handle: ResourceArc<NodeHandle>, topic: String) -> Result<bool, String> {
    send_cmd(&handle, Command::Subscribe { topic })?;
    Ok(true)
}

#[rustler::nif]
fn unsubscribe(handle: ResourceArc<NodeHandle>, topic: String) -> Result<bool, String> {
    send_cmd(&handle, Command::Unsubscribe { topic })?;
    Ok(true)
}

// ── GossipSub advanced ─────────────────────────────────────────

#[rustler::nif(schedule = "DirtyCpu")]
fn gossipsub_mesh_peers(handle: ResourceArc<NodeHandle>, topic: String) -> (rustler::Atom, Vec<String>) {
    match query(&handle, |tx| Command::GossipsubMeshPeers { topic, reply: tx }) {
        Some(peers) => (atoms::ok(), peer_ids_to_strings(peers)),
        None => (atoms::error(), Vec::new()),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn gossipsub_all_peers(handle: ResourceArc<NodeHandle>) -> (rustler::Atom, Vec<String>) {
    match query(&handle, |tx| Command::GossipsubAllPeers { reply: tx }) {
        Some(peers) => (atoms::ok(), peer_ids_to_strings(peers)),
        None => (atoms::error(), Vec::new()),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn gossipsub_peer_score(handle: ResourceArc<NodeHandle>, peer_id_str: String) -> (rustler::Atom, f64) {
    let peer_id: libp2p::PeerId = match peer_id_str.parse() {
        Ok(id) => id,
        Err(_) => return (atoms::error(), 0.0),
    };
    match query(&handle, |tx| Command::GossipsubPeerScore { peer_id, reply: tx }) {
        Some(score) => (atoms::ok(), score.unwrap_or(0.0)),
        None => (atoms::error(), 0.0),
    }
}

// ── DHT ─────────────────────────────────────────────────────────

#[rustler::nif]
fn dht_put(handle: ResourceArc<NodeHandle>, key: Binary, value: Binary) -> rustler::Atom {
    let _ = send_cmd(&handle, Command::DhtPut { key: key.as_slice().to_vec(), value: value.as_slice().to_vec() });
    atoms::ok()
}

#[rustler::nif]
fn dht_get(handle: ResourceArc<NodeHandle>, key: Binary) -> rustler::Atom {
    let _ = send_cmd(&handle, Command::DhtGet { key: key.as_slice().to_vec() });
    atoms::ok()
}

#[rustler::nif]
fn dht_find_peer(handle: ResourceArc<NodeHandle>, peer_id_str: String) -> rustler::Atom {
    let peer_id = match peer_id_str.parse::<libp2p::PeerId>() {
        Ok(id) => id,
        Err(_) => return atoms::error(),
    };
    let _ = send_cmd(&handle, Command::DhtFindPeer { peer_id });
    atoms::ok()
}

#[rustler::nif]
fn dht_provide(handle: ResourceArc<NodeHandle>, key: Binary) -> rustler::Atom {
    let _ = send_cmd(&handle, Command::DhtProvide { key: key.as_slice().to_vec() });
    atoms::ok()
}

#[rustler::nif]
fn dht_find_providers(handle: ResourceArc<NodeHandle>, key: Binary) -> rustler::Atom {
    let _ = send_cmd(&handle, Command::DhtFindProviders { key: key.as_slice().to_vec() });
    atoms::ok()
}

#[rustler::nif]
fn dht_bootstrap(handle: ResourceArc<NodeHandle>) -> rustler::Atom {
    let _ = send_cmd(&handle, Command::DhtBootstrap);
    atoms::ok()
}

// ── Request-Response RPC ────────────────────────────────────────

#[rustler::nif(schedule = "DirtyCpu")]
fn rpc_send_request(
    handle: ResourceArc<NodeHandle>,
    peer_id_str: String,
    data: Binary,
) -> (rustler::Atom, String) {
    let peer_id: libp2p::PeerId = match peer_id_str.parse() {
        Ok(id) => id,
        Err(_) => return (atoms::error(), "invalid_peer_id".to_string()),
    };
    let (tx, rx) = oneshot::channel();
    if send_cmd(
        &handle,
        Command::RpcSendRequest {
            peer_id,
            data: data.as_slice().to_vec(),
            reply: tx,
        },
    )
    .is_err()
    {
        return (atoms::error(), "node_stopped".to_string());
    }
    match rx.blocking_recv() {
        Ok(req_id) => (atoms::ok(), req_id),
        Err(_) => (atoms::error(), "node_stopped".to_string()),
    }
}

#[rustler::nif]
fn rpc_send_response(handle: ResourceArc<NodeHandle>, channel_id: String, data: Binary) -> rustler::Atom {
    let _ = send_cmd(
        &handle,
        Command::RpcSendResponse { channel_id, data: data.as_slice().to_vec() },
    );
    atoms::ok()
}

// ── Keypair (no handle needed) ──────────────────────────────────
// Return binaries via NewBinary for proper Elixir binary type.

#[rustler::nif(schedule = "DirtyCpu")]
fn generate_keypair<'a>(env: rustler::Env<'a>) -> rustler::Term<'a> {
    let keypair = libp2p::identity::Keypair::generate_ed25519();
    let peer_id = keypair.public().to_peer_id().to_base58();
    let public_key_bytes = keypair.public().encode_protobuf();

    match keypair.to_protobuf_encoding() {
        Ok(protobuf_bytes) => {
            let pub_bin = make_binary(env, &public_key_bytes);
            let proto_bin = make_binary(env, &protobuf_bytes);
            (atoms::ok(), pub_bin, peer_id, proto_bin).encode(env)
        }
        Err(_) => {
            let empty = make_binary(env, &[]);
            (atoms::error(), empty, "", empty).encode(env)
        }
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn keypair_from_protobuf<'a>(env: rustler::Env<'a>, bytes: Binary) -> rustler::Term<'a> {
    match libp2p::identity::Keypair::from_protobuf_encoding(bytes.as_slice()) {
        Ok(keypair) => {
            let peer_id = keypair.public().to_peer_id().to_base58();
            let public_key_bytes = keypair.public().encode_protobuf();
            let pub_bin = make_binary(env, &public_key_bytes);
            (atoms::ok(), pub_bin, peer_id).encode(env)
        }
        Err(_) => {
            (atoms::error(), atoms::invalid_peer_id()).encode(env)
        }
    }
}

fn make_binary<'a>(env: rustler::Env<'a>, data: &[u8]) -> rustler::Binary<'a> {
    let mut bin = rustler::NewBinary::new(env, data.len());
    bin.as_mut_slice().copy_from_slice(data);
    bin.into()
}

// ── Relay ───────────────────────────────────────────────────────

#[rustler::nif]
fn listen_via_relay(handle: ResourceArc<NodeHandle>, relay_addr: String) -> rustler::Atom {
    let addr = match relay_addr.parse::<libp2p::Multiaddr>() {
        Ok(a) => a,
        Err(_) => return atoms::error(),
    };
    let _ = send_cmd(&handle, Command::ListenViaRelay { relay_addr: addr });
    atoms::ok()
}

// ── Rendezvous ──────────────────────────────────────────────────

#[rustler::nif]
fn rendezvous_register(
    handle: ResourceArc<NodeHandle>,
    namespace: String,
    ttl: u64,
    rendezvous_peer_str: String,
) -> rustler::Atom {
    let rendezvous_peer = match rendezvous_peer_str.parse::<libp2p::PeerId>() {
        Ok(id) => id,
        Err(_) => return atoms::error(),
    };
    let _ = send_cmd(&handle, Command::RendezvousRegister { namespace, ttl, rendezvous_peer });
    atoms::ok()
}

#[rustler::nif]
fn rendezvous_discover(
    handle: ResourceArc<NodeHandle>,
    namespace: String,
    rendezvous_peer_str: String,
) -> rustler::Atom {
    let rendezvous_peer = match rendezvous_peer_str.parse::<libp2p::PeerId>() {
        Ok(id) => id,
        Err(_) => return atoms::error(),
    };
    let _ = send_cmd(&handle, Command::RendezvousDiscover { namespace, rendezvous_peer });
    atoms::ok()
}

#[rustler::nif]
fn rendezvous_unregister(
    handle: ResourceArc<NodeHandle>,
    namespace: String,
    rendezvous_peer_str: String,
) -> rustler::Atom {
    let rendezvous_peer = match rendezvous_peer_str.parse::<libp2p::PeerId>() {
        Ok(id) => id,
        Err(_) => return atoms::error(),
    };
    let _ = send_cmd(&handle, Command::RendezvousUnregister { namespace, rendezvous_peer });
    atoms::ok()
}

// ── Helpers ─────────────────────────────────────────────────────

fn send_cmd(
    handle: &ResourceArc<NodeHandle>,
    cmd: Command,
) -> Result<(), String> {
    // try_send: returns immediately, never blocks the BEAM scheduler.
    // Bounded channel provides backpressure — Full means the swarm is
    // behind on processing commands, Closed means the swarm loop exited.
    handle
        .cmd_tx
        .try_send(cmd)
        .map_err(|e| match e {
            tokio::sync::mpsc::error::TrySendError::Full(_) => {
                "command channel full — swarm is overloaded".to_string()
            }
            tokio::sync::mpsc::error::TrySendError::Closed(_) => {
                "node stopped — swarm event loop has exited".to_string()
            }
        })
}

// ── Init ────────────────────────────────────────────────────────

rustler::init!("Elixir.ExLibp2p.Native.Nif");

#[cfg(test)]
mod tests {
    #[test]
    fn test_module_compiles() {
        // Validates module structure compiles. NIF integration tested via ExUnit.
    }
}
