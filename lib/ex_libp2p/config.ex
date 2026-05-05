defmodule ExLibp2p.Config do
  @moduledoc """
  Centralized accessors for `ExLibp2p` application configuration.

  All `Application.get_env` / `fetch_env` reads for `:ex_libp2p` SHOULD route
  through this module. The benefit is grep-able boundary discipline: outside
  `lib/ex_libp2p/config.ex`, the codebase should not need to read app env
  directly. Run `grep -rn 'Application.get_env\\|Application.fetch_env' lib/`
  to audit.

  ## Scope at this milestone (M1)

  This is a deliberately small seed. Only `default_native_module/0` is exposed
  today. Future milestones will extend this module:

    * **M4** adds production-config accessors (`idle_connection_timeout_ms/0`,
      connection-limit defaults).
    * **M5** adds `keypair_storage/0` and `task_tracker_clock/0` once the
      `ExLibp2p.Keypair.Storage` and `ExLibp2p.Clock` behaviours land.

  Two existing `@default_native Application.compile_env(...)` reads in
  `keypair.ex` and `node.ex` are intentionally NOT migrated — they have
  compile-time semantics that are correct as-is. See
  `elixir-implementing` §10.5 for the `compile_env` vs `get_env` decision.

  ## Usage

      # Inside the library (or tests that want the canonical default)
      native = ExLibp2p.Config.default_native_module()

      # Tests that swap the NIF backend continue to pass `native_module:` as
      # an explicit option to `ExLibp2p.Node.start_link/1` — the accessor here
      # is for code paths that don't have an explicit option to forward.
  """

  @default_native_module ExLibp2p.Native.Nif
  @default_keypair_storage ExLibp2p.Keypair.Storage.File
  @default_task_tracker_clock ExLibp2p.Clock.System

  @doc """
  Returns the configured default `Native.*` backend module.

  Reads `:ex_libp2p` → `:native_module` at runtime, falling back to
  `ExLibp2p.Native.Nif` when unset. Runtime read is intentional — tests can
  swap via `Application.put_env/3` without recompilation.
  """
  @spec default_native_module() :: module()
  def default_native_module,
    do: Application.get_env(:ex_libp2p, :native_module, @default_native_module)

  @doc """
  Returns the configured `ExLibp2p.Keypair.Storage` implementation.

  Reads `:ex_libp2p` → `ExLibp2p.Keypair` → `:storage` at runtime,
  falling back to `ExLibp2p.Keypair.Storage.File`.
  """
  @spec keypair_storage() :: module()
  def keypair_storage do
    :ex_libp2p
    |> Application.get_env(ExLibp2p.Keypair, [])
    |> Keyword.get(:storage, @default_keypair_storage)
  end

  @doc """
  Returns the configured `ExLibp2p.Clock` implementation used by
  `ExLibp2p.OTP.TaskTracker`.

  Reads `:ex_libp2p` → `ExLibp2p.OTP.TaskTracker` → `:clock` at runtime,
  falling back to `ExLibp2p.Clock.System`.
  """
  @spec task_tracker_clock() :: module()
  def task_tracker_clock do
    :ex_libp2p
    |> Application.get_env(ExLibp2p.OTP.TaskTracker, [])
    |> Keyword.get(:clock, @default_task_tracker_clock)
  end

  @doc """
  Returns the configured storage adapter for the DHT routing-table
  snapshot file. Defaults to `ExLibp2p.Keypair.Storage.File` (the same
  atomic-write implementation used for the keypair file). Tests can
  swap to an in-memory mock without affecting `keypair_storage/0`.

  Reads `:ex_libp2p` → `ExLibp2p.Node.DhtState` → `:storage` at runtime.
  """
  @spec dht_state_storage() :: module()
  def dht_state_storage do
    :ex_libp2p
    |> Application.get_env(ExLibp2p.Node.DhtState, [])
    |> Keyword.get(:storage, @default_keypair_storage)
  end
end
