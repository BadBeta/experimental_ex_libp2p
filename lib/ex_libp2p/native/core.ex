defmodule ExLibp2p.Native.Core do
  @moduledoc """
  Behaviour for core node lifecycle operations.

  Covers starting/stopping nodes, peer identity, connectivity, and event handling.
  """

  @type handle :: reference()

  @callback start_node(map()) :: {:ok, handle()} | {:error, term()}
  @callback stop_node(handle()) :: :ok
  @callback register_event_handler(handle(), pid()) :: :ok
  @callback get_peer_id(handle()) :: String.t()
  @callback connected_peers(handle()) :: [String.t()]
  @callback listening_addrs(handle()) :: [String.t()]
  @callback dial(handle(), String.t()) :: :ok | {:error, atom()}
end
