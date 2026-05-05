defmodule ExLibp2p.Application do
  @moduledoc false
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Start order is dependency order. HandlerRegistry MUST start before any
    # ExLibp2p.Node so nodes can dispatch into it from `init/1` onward.
    # :rest_for_one so a HandlerRegistry crash also restarts the
    # DynamicSupervisor — its children would otherwise hold stale references.
    children = [
      {Registry, keys: :unique, name: ExLibp2p.Registry},
      ExLibp2p.Node.HandlerRegistry,
      {DynamicSupervisor, name: ExLibp2p.NodeSupervisor, strategy: :one_for_one}
    ]

    Supervisor.start_link(children, strategy: :rest_for_one, name: ExLibp2p.Supervisor)
  end

  @impl true
  def stop(_state) do
    # Per-node cleanup runs in `ExLibp2p.Node.terminate/2` (HandlerRegistry
    # subscription drop + NIF stop_node). The Application callback logs a
    # single boundary line so operators can see the system shutdown reason
    # in production logs without reconstructing it from per-process exits.
    Logger.info("[ExLibp2p] application stopping")
    :ok
  end
end
