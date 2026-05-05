defmodule ExLibp2p.Node.NifOps do
  @moduledoc false
  # Direct NIF passthrough `handle_call/3` clauses for protocol-level operations
  # that don't touch Node's internal state (handlers, monitors). Covers DHT,
  # Request-Response RPC, GossipSub pub/sub + introspection, bandwidth metrics,
  # and Rendezvous client. Each clause is a thin "take handle, call native,
  # return result" wrapper.

  alias ExLibp2p.Node.Result

  @doc "Handles a NifOps `handle_call/3` message. Catch-all returns `{:error, :unknown_call}`."
  @spec handle(term(), GenServer.from(), ExLibp2p.Node.t()) ::
          {:reply, term(), ExLibp2p.Node.t()}

  # GossipSub pub/sub
  def handle({:publish, topic, data}, _from, state) do
    {:reply, Result.normalize_ok(state.native.publish(state.handle, topic, data)), state}
  end

  def handle({:subscribe, topic}, _from, state) do
    {:reply, Result.normalize_ok(state.native.subscribe(state.handle, topic)), state}
  end

  def handle({:unsubscribe, topic}, _from, state) do
    {:reply, Result.normalize_ok(state.native.unsubscribe(state.handle, topic)), state}
  end

  # GossipSub introspection
  def handle({:gossipsub_mesh_peers, topic}, _from, state) do
    {:reply, state.native.gossipsub_mesh_peers(state.handle, topic), state}
  end

  def handle(:gossipsub_all_peers, _from, state) do
    {:reply, state.native.gossipsub_all_peers(state.handle), state}
  end

  def handle({:gossipsub_peer_score, peer_id_str}, _from, state) do
    {:reply, state.native.gossipsub_peer_score(state.handle, peer_id_str), state}
  end

  # DHT
  def handle({:dht_put, key, value}, _from, state) do
    {:reply, state.native.dht_put(state.handle, key, value), state}
  end

  def handle({:dht_get, key}, _from, state) do
    {:reply, state.native.dht_get(state.handle, key), state}
  end

  def handle({:dht_find_peer, peer_id_str}, _from, state) do
    {:reply, state.native.dht_find_peer(state.handle, peer_id_str), state}
  end

  def handle({:dht_provide, key}, _from, state) do
    {:reply, state.native.dht_provide(state.handle, key), state}
  end

  def handle({:dht_find_providers, key}, _from, state) do
    {:reply, state.native.dht_find_providers(state.handle, key), state}
  end

  def handle(:dht_bootstrap, _from, state) do
    {:reply, state.native.dht_bootstrap(state.handle), state}
  end

  # Request-Response RPC
  def handle({:rpc_send_request, peer_id_str, data}, _from, state) do
    {:reply, state.native.rpc_send_request(state.handle, peer_id_str, data), state}
  end

  def handle({:rpc_send_response, channel_id, data}, _from, state) do
    {:reply, state.native.rpc_send_response(state.handle, channel_id, data), state}
  end

  # Metrics
  def handle(:bandwidth_stats, _from, state) do
    {:reply, state.native.bandwidth_stats(state.handle), state}
  end

  def handle(:prometheus_metrics, _from, state) do
    {:reply, state.native.prometheus_metrics(state.handle), state}
  end

  # Rendezvous client
  def handle({:rendezvous_register, namespace, ttl, rendezvous_peer}, _from, state) do
    {:reply, state.native.rendezvous_register(state.handle, namespace, ttl, rendezvous_peer), state}
  end

  def handle({:rendezvous_discover, namespace, rendezvous_peer}, _from, state) do
    {:reply, state.native.rendezvous_discover(state.handle, namespace, rendezvous_peer), state}
  end

  def handle({:rendezvous_unregister, namespace, rendezvous_peer}, _from, state) do
    {:reply, state.native.rendezvous_unregister(state.handle, namespace, rendezvous_peer), state}
  end

  # unknown payload here. Keeps the GenServer alive instead of FunctionClauseError.
  def handle(unknown, _from, state) do
    require Logger
    Logger.warning("[ExLibp2p.Node.NifOps] Unknown call: #{inspect(unknown)}")
    {:reply, {:error, :unknown_call}, state}
  end
end
