# ExLibp2p — Archdo Architectural Review

**Date:** 2026-04-19
**Tool:** Archdo 0.1.0 (AST + compiled analysis)
**Elixir:** 1.19.5, OTP 28

## Summary

| Severity | Count | Key Areas |
|----------|-------|-----------|
| Error | 1 | Config struct too large (33 fields) |
| Warning | 12 | NIF panics (3), missing :DOWN handler, duplicated code, library config, broad imports |
| Info | 273 | GenServer.call resilience (37+35), dead code (79), phantom deps (56), non-exhaustive API (8) |
| **Total** | **286** | |

## Critical Fixes (do first)

### 1. GenServer.call resilience — 37 unprotected calls

Every client API function in Node, DHT, Discovery, Health, Gossipsub, TaskTracker calls
`GenServer.call(node, msg)` with a variable PID and no `catch :exit`. If the process dies
between resolution and call, the caller crashes with an exit signal.

**Fix:** Add a `safe_call/3` helper and use it everywhere:

```elixir
# In lib/ex_libp2p/node.ex (or a shared helper module)
defp safe_call(server, message, timeout \\ 15_000) do
  GenServer.call(server, message, timeout)
catch
  :exit, reason -> {:error, {:node_down, reason}}
end
```

Then replace all bare `GenServer.call(node, msg)` with `safe_call(node, msg)`.

This fixes both rule 6.16 (catch :exit) and rule 4.18 (explicit timeout) in one change.

**Affected files:**
- `lib/ex_libp2p/node.ex` — 24 calls
- `lib/ex_libp2p/dht.ex` — 6 calls
- `lib/ex_libp2p/discovery.ex` — 1 call
- `lib/ex_libp2p/health.ex` — 2 calls
- `lib/ex_libp2p/otp/task_tracker.ex` — 7 calls
- `lib/ex_libp2p/otp/distribution.ex` — 1 call

### 2. NIF panic patterns — 3 VM-killing unwrap/expect calls

```
native/ex_libp2p_nif/src/events.rs:267  — .unwrap()
native/ex_libp2p_nif/src/events.rs:423  — .unwrap()
native/ex_libp2p_nif/src/node.rs:31     — .expect()
```

**Fix:** Replace with `?` operator or match-and-return-error:

```rust
// BAD
let result = some_call().unwrap();

// GOOD
let result = some_call().map_err(|e| rustler::Error::Term(Box::new(format!("{}", e))))?;
```

### 3. Process.monitor without :DOWN handler

`lib/ex_libp2p/node.ex:317` — calls `Process.monitor` but no `handle_info({:DOWN, ...})`
clause exists. Monitored :DOWN messages pile up in the mailbox.

**Fix:** Add a `handle_info` clause:

```elixir
@impl true
def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
  Logger.warning("Monitored process died: #{inspect(reason)}")
  {:noreply, handle_process_down(state, reason)}
end
```

### 4. Config struct — 33 fields

`ExLibp2p.Node.Config` has 33 fields — too many for a single struct.

**Fix:** Split into focused sub-configs:

```elixir
defmodule ExLibp2p.Node.Config do
  defstruct [
    :network,     # %NetworkConfig{listen_addrs, bootstrap_peers, ...}
    :gossipsub,   # %GossipsubConfig{mesh_n, heartbeat_interval, ...}
    :dht,         # %DHTConfig{mode, protocol, ...}
    :security,    # %SecurityConfig{keypair, pnet_key, ...}
    :limits,      # %LimitsConfig{max_connections, max_streams, ...}
    :identity     # %IdentityConfig{agent_version, ...}
  ]
end
```

## Architecture Improvements

### 5. Native behaviour — 28 callbacks (rule 4.1)

`ExLibp2p.Native` defines 28 required callbacks — violates Interface Segregation.

**Fix:** Split into focused behaviours:

```elixir
defmodule ExLibp2p.Native.Core do
  @callback start_node(map()) :: {:ok, reference()} | {:error, term()}
  @callback stop_node(reference()) :: :ok
  @callback get_peer_id(reference()) :: String.t()
  @callback connected_peers(reference()) :: [String.t()]
  @callback listening_addrs(reference()) :: [String.t()]
  @callback dial(reference(), String.t()) :: :ok | {:error, atom()}
end

defmodule ExLibp2p.Native.Pubsub do
  @callback publish(reference(), String.t(), binary()) :: :ok | {:error, atom()}
  @callback subscribe(reference(), String.t()) :: :ok | {:error, atom()}
  @callback unsubscribe(reference(), String.t()) :: :ok | {:error, atom()}
  # ... gossipsub-specific callbacks
end

defmodule ExLibp2p.Native.DHT do
  @callback dht_put(reference(), binary(), binary()) :: :ok | {:error, atom()}
  @callback dht_get(reference(), binary()) :: :ok | {:error, atom()}
  # ...
end
```

### 6. Missing telemetry — Node (47 functions) and Gossipsub (4 functions)

No `:telemetry.execute` or `:telemetry.span` in the two most important modules.

**Fix:** Add telemetry to key operations:

```elixir
def dial(node, addr) when is_binary(addr) do
  :telemetry.span([:ex_libp2p, :node, :dial], %{addr: addr}, fn ->
    result = safe_call(node, {:dial, addr})
    {result, %{}}
  end)
end
```

### 7. Keypair mixes error styles (rule 6.11)

`ExLibp2p.Keypair` has both ok/error functions (`generate/0`) and bang functions (`load!/1`)
but inconsistently — `load!/1` exists but there's no `load/1`.

**Fix:** Add the non-bang variant and follow the pair convention:

```elixir
def load(path) do
  case File.read(path) do
    {:ok, data} -> from_protobuf(data)
    {:error, reason} -> {:error, {:file_error, reason}}
  end
end

def load!(path) do
  case load(path) do
    {:ok, keypair} -> keypair
    {:error, reason} -> raise "Failed to load keypair: #{inspect(reason)}"
  end
end
```

### 8. Library reads Application config directly (rule 3.3)

`lib/ex_libp2p/keypair.ex:131` — calls `Application.get_env` for key path.
Libraries should accept config via function arguments, not Application env.

**Fix:** Accept path as parameter with optional Application.get_env fallback:

```elixir
def default_path do
  Application.get_env(:ex_libp2p, :keypair_path, Path.join(System.user_home!(), ".ex_libp2p/keypair"))
end

def load!(path \\ default_path()) do
  # ...
end
```

## Compiled Analysis Findings

### Dead code (79 functions)

Many are expected for a library (public API not yet used internally).
Key ones to verify:
- `ExLibp2p.Node.Config.new/0` — unused constructor
- `ExLibp2p.Relay.*` — entire Relay module appears unused
- `ExLibp2p.Health.check/1` — health check never called

### Non-exhaustive public API (8 functions)

Public functions with multi-clause dispatch but no catch-all.
Review each — some may be intentional (closed dispatch).

### Context quality (2 issues)

Context discovery found cohesion/boundary issues worth reviewing.
