defmodule ExLibp2p.Call do
  @moduledoc false

  # Resilient GenServer.call wrapper for all client API modules.
  #
  # Every call to a libp2p node GenServer targets a variable PID (or name)
  # that may have crashed. This wrapper catches :exit signals from dead
  # processes and returns {:error, {:node_unavailable, reason}} instead
  # of crashing the caller.
  #
  # Usage:
  #   import ExLibp2p.Call, only: [safe_call: 2, safe_call: 3]
  #   def peer_id(node), do: safe_call(node, :peer_id)

  @default_timeout 15_000

  @doc false
  @spec safe_call(GenServer.server(), term(), timeout()) ::
          term() | {:error, {:node_unavailable, term()}}
  def safe_call(server, message, timeout \\ @default_timeout) do
    GenServer.call(server, message, timeout)
  catch
    :exit, reason -> {:error, {:node_unavailable, reason}}
  end
end
