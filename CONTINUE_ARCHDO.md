# ExLibp2p — Continue Archdo Review Fixes

## MANDATORY: Read Before Writing Any Code

1. **Load `/elixir` skill FIRST.** Then read these subskills:
   - `~/.claude/skills/elixir/architecture-reference.md` — boundaries, pure core/impure shell
   - `~/.claude/skills/elixir/otp-reference.md` — GenServer, supervision patterns
   - `~/.claude/skills/elixir/language-patterns.md` — comprehensions, pipeline, error handling
2. **Load `/libp2p` skill** for libp2p-specific patterns.
3. **Do NOT delegate to subagents.** Write all code yourself with skills in context.
4. **Do it properly the first time.** Follow the Elixir skill decision tables.

## Project Location

- **Project root:** `/home/vidar/Projects/ex_libp2p`
- **Elixir version:** 1.19.5 (via mise: `mise exec -- mix ...`)
- **Build flag:** `EX_LIBP2P_BUILD=1` needed for Rust NIF compilation
- **Compile:** `cd /home/vidar/Projects/ex_libp2p && EX_LIBP2P_BUILD=1 mise exec -- mix compile`
- **Test:** `cd /home/vidar/Projects/ex_libp2p && EX_LIBP2P_BUILD=1 mise exec -- mix test`
- **Archdo:** From Archdo dir: `mix archdo --paths /home/vidar/Projects/ex_libp2p/lib --compiled --format compact`

## Current State (2026-04-19)

- **Archdo findings: 106 → 21** (80% reduction across 3 commits)
- **Tests: 148 passing + 14 doctests** (1 pre-existing config test failure unrelated to our changes)
- **NIF panics: 3 → 0** (all .unwrap()/.expect() eliminated)
- **GenServer.call resilience: 72 → 8** (safe_call helper applied everywhere except Distribution)

### Commits Applied

1. `ff76927` — safe_call resilience + NIF panic elimination (main fix)
2. `75979c2` — Keypair error consistency, narrow imports, telemetry, config
3. `7ac0c52` — safe_call for RequestResponse and Health.check

## Remaining Findings (21)

### Architectural (fix when ready)

| Rule | Finding | Recommendation |
|------|---------|----------------|
| **4.1** | `ExLibp2p.Native` has 28 required callbacks | Split into focused behaviours: Core (6), Pubsub (6), DHT (6), RPC (2), Keypair (2), Relay (1), Rendezvous (3), Metrics (1) |
| **6.3** | `ExLibp2p.Node.Config` has 33 fields | Skip per user request |

### Tolerable (intentional design)

| Rule | Finding | Why tolerable |
|------|---------|---------------|
| 6.8 ×3 | Zone of pain metrics (Call, PeerId, ExLibp2p) | Core utility modules — stable and rarely change |
| 1.11 ×3 | Anemic context (gossipsub/, native/, node/) | Subdirectories with focused contents — not god contexts |
| 6.16 ×2 | GenServer.call in Distribution without catch :exit | Has its own `safe_call` with different error contract |
| 4.8 ×2 | Direct File I/O in keypair | Necessary — keypair storage IS file I/O |
| 4.19 ×2 | Missing telemetry in Node/Gossipsub | Telemetry IS in Node (added in commit 2), but Archdo's AST detection doesn't see `:telemetry.span` (uses Erlang module syntax) |
| 3.1 ×2 | Structurally similar protocol impls | Jason.Encoder for Multiaddr/PeerId — each struct needs its own defimpl |
| 6.2 | Distribution.call complexity 10 (limit 9) | Barely over — inherent to request/receive/decode protocol |
| 6.11 | Keypair error style inconsistency | Detection lag — save/2 was added but rule still sees mixed styles |
| 5.6 | Default supervisor restart budget | Acceptable for application supervisor |
| 3.2 | System.get_env in Rustler config | Compile-time build flag — standard Rustler pattern |
| 1.9 | Hardcoded clock in TaskTracker | System.monotonic_time in task dispatch timestamp |

## Next Fix: Native Behaviour Split (Rule 4.1)

The `ExLibp2p.Native` behaviour defines 28 callbacks — all NIF functions in one interface. Split into focused behaviours per the Interface Segregation Principle.

### Target Structure

```
lib/ex_libp2p/native.ex           → split into:
lib/ex_libp2p/native/core.ex       — 6 callbacks (start_node, stop_node, get_peer_id, connected_peers, listening_addrs, dial)
lib/ex_libp2p/native/pubsub.ex     — 6 callbacks (publish, subscribe, unsubscribe, gossipsub_mesh_peers, gossipsub_all_peers, gossipsub_peer_score)
lib/ex_libp2p/native/dht.ex        — 6 callbacks (dht_put, dht_get, dht_find_peer, dht_provide, dht_find_providers, dht_bootstrap)
lib/ex_libp2p/native/rpc.ex        — 2 callbacks (rpc_send_request, rpc_send_response)
lib/ex_libp2p/native/keypair.ex    — 2 callbacks (generate_keypair, keypair_from_protobuf)
lib/ex_libp2p/native/relay.ex      — 1 callback (listen_via_relay)
lib/ex_libp2p/native/rendezvous.ex — 3 callbacks (rendezvous_register, rendezvous_discover, rendezvous_unregister)
lib/ex_libp2p/native/metrics.ex    — 2 callbacks (bandwidth_stats, register_event_handler)
```

### Files to Update

- `lib/ex_libp2p/native.ex` — replace single behaviour with module that groups the sub-behaviours
- `lib/ex_libp2p/native/nif.ex` — add multiple `@behaviour` declarations
- `test/ex_libp2p/native/mock.ex` or similar — mock only needed behaviours per test
- `lib/ex_libp2p/node.ex` — update `@impl true` annotations if needed

### Implementation Steps

1. Create the 8 focused behaviour modules with `@callback` definitions
2. Update `ExLibp2p.Native.Nif` to declare all 8 `@behaviour` annotations
3. Update all `@impl true` to `@impl ExLibp2p.Native.Core` etc. for clarity
4. Update mock module(s) to implement only relevant behaviours
5. Run tests: `EX_LIBP2P_BUILD=1 mise exec -- mix test`
6. Run Archdo: verify rule 4.1 no longer fires

## Archdo Detection Gaps to Fix

These were identified during the ex_libp2p review:

1. **Rule 4.19 (missing telemetry)** — doesn't detect `:telemetry.span(...)` or `:telemetry.execute(...)` Erlang-style module calls. The AST pattern looks for `Telemetry.execute` but not `:telemetry.execute`. Fix in `lib/archdo/rules/module/missing_telemetry.ex`.

2. **Rule 6.11 (inconsistent error style)** — may need recalibration. After adding `save/2` alongside `save!/2`, the rule still flags Keypair. Check if it properly detects matching bang/non-bang pairs.

## Archdo False Positives Fixed (2026-04-19)

These were found and fixed during this session:

1. **Rule 4.5** — `import Module, only: [...]` not detected when `literal_encoder` wraps `:only` in `{:__block__, _, [:only]}`. Fixed with `has_keyword_key?/2`.

2. **Rule 5.20** — `:DOWN` atom in `handle_info` patterns wrapped in `{:__block__, _, [:DOWN]}` by `literal_encoder`. Added matching clause for wrapped form.
