defmodule ExLibp2p.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: ExLibp2p.Registry},
      {DynamicSupervisor, name: ExLibp2p.NodeSupervisor, strategy: :one_for_one}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ExLibp2p.Supervisor)
  end
end
