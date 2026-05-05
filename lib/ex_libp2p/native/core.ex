defmodule ExLibp2p.Native.Core do
  @moduledoc """
  Behaviour for core node lifecycle operations.

  Covers starting/stopping nodes, peer identity, connectivity, and event handling.
  """

  @type handle :: reference()

  # Returns the NIF handle directly on success; the real NIF raises
  # `ErlangError` on failure. `Node.init/1` rescues to support either path.
  @callback start_node(map()) :: handle() | {:error, term()}
  @callback stop_node(handle()) :: :ok
  @callback register_event_handler(handle(), pid()) :: :ok
  @callback get_peer_id(handle()) :: String.t()
  @callback connected_peers(handle()) :: [String.t()]
  @callback listening_addrs(handle()) :: [String.t()]
  @callback dial(handle(), String.t()) :: :ok | {:error, term()}
end
