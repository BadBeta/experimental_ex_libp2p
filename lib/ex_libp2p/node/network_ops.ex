defmodule ExLibp2p.Node.NetworkOps do
  @moduledoc false
  # Connection-management `handle_call/3` clauses extracted from `ExLibp2p.Node`
  # to keep the dispatcher under §5.43's callback-sprawl threshold while
  # preserving the public API on `ExLibp2p.Node` (callers continue to send
  # `{:dial, addr}`, `:peer_id`, etc.).

  alias ExLibp2p.Node.Result
  alias ExLibp2p.PeerId

  @doc "Returns `true` iff this module handles the given call payload."
  @spec handles?(term()) :: boolean()
  def handles?(:peer_id), do: true
  def handles?(:connected_peers), do: true
  def handles?(:listening_addrs), do: true
  def handles?({:dial, _}), do: true
  def handles?({:listen_via_relay, _}), do: true
  def handles?(_), do: false

  @doc "Handles a NetworkOps `handle_call/3` message. Same return shape as `GenServer.handle_call/3`."
  @spec handle(term(), GenServer.from(), ExLibp2p.Node.t()) ::
          {:reply, term(), ExLibp2p.Node.t()}
  def handle(:peer_id, _from, state) do
    {:reply, {:ok, state.peer_id}, state}
  end

  def handle(:connected_peers, _from, state) do
    peers = Enum.map(state.native.connected_peers(state.handle), &PeerId.new!/1)
    {:reply, {:ok, peers}, state}
  end

  def handle(:listening_addrs, _from, state) do
    addrs = state.native.listening_addrs(state.handle)
    {:reply, {:ok, addrs}, state}
  end

  def handle({:dial, addr}, _from, state) do
    result = Result.normalize_ok(state.native.dial(state.handle, addr))
    {:reply, result, state}
  end

  def handle({:listen_via_relay, relay_addr}, _from, state) do
    result = state.native.listen_via_relay(state.handle, relay_addr)
    {:reply, result, state}
  end
end
