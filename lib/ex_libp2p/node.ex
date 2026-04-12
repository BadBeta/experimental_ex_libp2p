defmodule ExLibp2p.Node do
  @moduledoc """
  GenServer wrapping a libp2p node.

  Manages the lifecycle of a libp2p node, dispatches network events to
  registered handler processes, and provides the client API for all
  node operations.

  ## Starting a Node

      {:ok, node} = ExLibp2p.Node.start_link(
        listen_addrs: ["/ip4/0.0.0.0/tcp/0"],
        gossipsub_topics: ["my-topic"],
        enable_mdns: true
      )

  ## Event Handling

  Register to receive specific event types:

      ExLibp2p.Node.register_handler(node, :gossipsub_message)

  Events arrive as `{:libp2p, event_type, event_struct}` messages.

  Handler processes are monitored — when a handler exits, it is automatically
  removed. No dead PIDs accumulate over time.
  """

  use GenServer
  require Logger

  alias ExLibp2p.Multiaddr
  alias ExLibp2p.Node.Config
  alias ExLibp2p.Node.Event
  alias ExLibp2p.PeerId

  @default_native Application.compile_env(:ex_libp2p, :native_module, ExLibp2p.Native.Nif)

  # event_handlers: %{event_type => [{pid, monitor_ref}]}
  # monitors: %{monitor_ref => {pid, event_type}} — reverse index for :DOWN cleanup
  defstruct [:handle, :peer_id, :native, event_handlers: %{}, monitors: %{}]

  @type t :: %__MODULE__{
          handle: reference() | nil,
          peer_id: PeerId.t() | nil,
          native: module(),
          event_handlers: %{atom() => [{pid(), reference()}]},
          monitors: %{reference() => {pid(), atom()}}
        }

  # --- Client API ---

  @doc "Starts a new libp2p node as a linked process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, node_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, node_opts, gen_opts)
  end

  @doc """
  Starts a node under the `ExLibp2p.NodeSupervisor` DynamicSupervisor.

  The node will be restarted automatically if it crashes. Options are
  the same as `start_link/1`.
  """
  @spec start_supervised(keyword()) :: DynamicSupervisor.on_start_child()
  def start_supervised(opts \\ []) do
    DynamicSupervisor.start_child(ExLibp2p.NodeSupervisor, {__MODULE__, opts})
  end

  @doc "Returns the node's peer ID."
  @spec peer_id(GenServer.server()) :: {:ok, PeerId.t()} | {:error, term()}
  def peer_id(node), do: GenServer.call(node, :peer_id)

  @doc "Returns the list of currently connected peers."
  @spec connected_peers(GenServer.server()) :: {:ok, [PeerId.t()]} | {:error, term()}
  def connected_peers(node), do: GenServer.call(node, :connected_peers)

  @doc "Returns the addresses this node is listening on."
  @spec listening_addrs(GenServer.server()) :: {:ok, [String.t()]} | {:error, term()}
  def listening_addrs(node), do: GenServer.call(node, :listening_addrs)

  @doc """
  Dials a peer at the given multiaddr.

  The multiaddr should include a `/p2p/<peer_id>` component for direct dialing.
  """
  @spec dial(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def dial(node, addr) when is_binary(addr) do
    case Multiaddr.new(addr) do
      {:ok, _} -> GenServer.call(node, {:dial, addr})
      {:error, _} -> {:error, :invalid_multiaddr}
    end
  end

  @doc "Publishes binary data to a GossipSub topic."
  @spec publish(GenServer.server(), String.t(), binary()) :: :ok | {:error, term()}
  def publish(node, topic, data) when is_binary(topic) and is_binary(data) do
    GenServer.call(node, {:publish, topic, data})
  end

  @doc "Subscribes to a GossipSub topic."
  @spec subscribe(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def subscribe(node, topic) when is_binary(topic) do
    GenServer.call(node, {:subscribe, topic})
  end

  @doc "Unsubscribes from a GossipSub topic."
  @spec unsubscribe(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def unsubscribe(node, topic) when is_binary(topic) do
    GenServer.call(node, {:unsubscribe, topic})
  end

  @doc """
  Registers the calling process (or `pid`) to receive events of the given type.

  The handler is monitored — if the process exits, it is automatically removed.
  Re-registering the same pid for the same event type is a no-op.

  Event types: `:connection_established`, `:connection_closed`, `:new_listen_addr`,
  `:gossipsub_message`, `:peer_discovered`, `:dht_query_result`
  """
  @spec register_handler(GenServer.server(), atom(), pid()) :: :ok
  def register_handler(node, event_type, pid \\ self()) do
    GenServer.call(node, {:register_handler, event_type, pid})
  end

  @doc "Unregisters the calling process from receiving events of the given type."
  @spec unregister_handler(GenServer.server(), atom(), pid()) :: :ok
  def unregister_handler(node, event_type, pid \\ self()) do
    GenServer.call(node, {:unregister_handler, event_type, pid})
  end

  @doc "Stops the node gracefully."
  @spec stop(GenServer.server()) :: :ok
  def stop(node), do: GenServer.stop(node)

  # --- Internal client API (used by context modules, not public) ---

  @doc false
  @spec gossipsub_mesh_peers(GenServer.server(), String.t()) ::
          {:ok, [String.t()]} | {:error, term()}
  def gossipsub_mesh_peers(node, topic),
    do: GenServer.call(node, {:gossipsub_mesh_peers, topic})

  @doc false
  @spec gossipsub_all_peers(GenServer.server()) :: {:ok, [String.t()]} | {:error, term()}
  def gossipsub_all_peers(node), do: GenServer.call(node, :gossipsub_all_peers)

  @doc false
  @spec gossipsub_peer_score(GenServer.server(), String.t()) :: {:ok, float()} | {:error, term()}
  def gossipsub_peer_score(node, peer_id_str),
    do: GenServer.call(node, {:gossipsub_peer_score, peer_id_str})

  @doc false
  @spec bandwidth_stats(GenServer.server()) ::
          {:ok, non_neg_integer(), non_neg_integer()} | {:error, term()}
  def bandwidth_stats(node), do: GenServer.call(node, :bandwidth_stats)

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    native = Keyword.get(opts, :native_module, @default_native)
    config_opts = Keyword.drop(opts, [:native_module])
    config = Config.new(config_opts)

    with {:ok, valid_config} <- Config.validate(config),
         config_map = valid_config |> Map.from_struct() |> stringify_keys(),
         {:ok, handle} <- native.start_node(config_map),
         peer_id_str = native.get_peer_id(handle),
         {:ok, peer_id} <- PeerId.new(peer_id_str) do
      native.register_event_handler(handle, self())

      Logger.info("[ExLibp2p] Node started: #{peer_id_str}")

      {:ok,
       %__MODULE__{
         handle: handle,
         peer_id: peer_id,
         native: native
       }}
    else
      {:error, reason} -> {:stop, {:failed_to_start, reason}}
    end
  end

  @impl true
  def handle_call(:peer_id, _from, state) do
    {:reply, {:ok, state.peer_id}, state}
  end

  def handle_call(:connected_peers, _from, state) do
    peers = Enum.map(state.native.connected_peers(state.handle), &PeerId.new!/1)
    {:reply, {:ok, peers}, state}
  end

  def handle_call(:listening_addrs, _from, state) do
    addrs = state.native.listening_addrs(state.handle)
    {:reply, {:ok, addrs}, state}
  end

  def handle_call({:dial, addr}, _from, state) do
    result = normalize_ok(state.native.dial(state.handle, addr))
    {:reply, result, state}
  end

  def handle_call({:publish, topic, data}, _from, state) do
    result = normalize_ok(state.native.publish(state.handle, topic, data))
    {:reply, result, state}
  end

  def handle_call({:subscribe, topic}, _from, state) do
    result = normalize_ok(state.native.subscribe(state.handle, topic))
    {:reply, result, state}
  end

  def handle_call({:unsubscribe, topic}, _from, state) do
    result = normalize_ok(state.native.unsubscribe(state.handle, topic))
    {:reply, result, state}
  end

  # DHT operations
  def handle_call({:dht_put, key, value}, _from, state) do
    result = state.native.dht_put(state.handle, key, value)
    {:reply, result, state}
  end

  def handle_call({:dht_get, key}, _from, state) do
    result = state.native.dht_get(state.handle, key)
    {:reply, result, state}
  end

  def handle_call({:dht_find_peer, peer_id_str}, _from, state) do
    result = state.native.dht_find_peer(state.handle, peer_id_str)
    {:reply, result, state}
  end

  def handle_call({:dht_provide, key}, _from, state) do
    result = state.native.dht_provide(state.handle, key)
    {:reply, result, state}
  end

  def handle_call({:dht_find_providers, key}, _from, state) do
    result = state.native.dht_find_providers(state.handle, key)
    {:reply, result, state}
  end

  def handle_call(:dht_bootstrap, _from, state) do
    result = state.native.dht_bootstrap(state.handle)
    {:reply, result, state}
  end

  # Request-Response RPC
  def handle_call({:rpc_send_request, peer_id_str, data}, _from, state) do
    result = state.native.rpc_send_request(state.handle, peer_id_str, data)
    {:reply, result, state}
  end

  def handle_call({:rpc_send_response, channel_id, data}, _from, state) do
    result = state.native.rpc_send_response(state.handle, channel_id, data)
    {:reply, result, state}
  end

  # Relay
  def handle_call({:listen_via_relay, relay_addr}, _from, state) do
    result = state.native.listen_via_relay(state.handle, relay_addr)
    {:reply, result, state}
  end

  # GossipSub advanced
  def handle_call({:gossipsub_mesh_peers, topic}, _from, state) do
    result = state.native.gossipsub_mesh_peers(state.handle, topic)
    {:reply, result, state}
  end

  def handle_call(:gossipsub_all_peers, _from, state) do
    result = state.native.gossipsub_all_peers(state.handle)
    {:reply, result, state}
  end

  def handle_call({:gossipsub_peer_score, peer_id_str}, _from, state) do
    result = state.native.gossipsub_peer_score(state.handle, peer_id_str)
    {:reply, result, state}
  end

  # Metrics
  def handle_call(:bandwidth_stats, _from, state) do
    result = state.native.bandwidth_stats(state.handle)
    {:reply, result, state}
  end

  # Rendezvous
  def handle_call({:rendezvous_register, namespace, ttl, rendezvous_peer}, _from, state) do
    result = state.native.rendezvous_register(state.handle, namespace, ttl, rendezvous_peer)
    {:reply, result, state}
  end

  def handle_call({:rendezvous_discover, namespace, rendezvous_peer}, _from, state) do
    result = state.native.rendezvous_discover(state.handle, namespace, rendezvous_peer)
    {:reply, result, state}
  end

  def handle_call({:rendezvous_unregister, namespace, rendezvous_peer}, _from, state) do
    result = state.native.rendezvous_unregister(state.handle, namespace, rendezvous_peer)
    {:reply, result, state}
  end

  def handle_call({:register_handler, event_type, pid}, _from, state) do
    case already_registered?(state, event_type, pid) do
      true ->
        {:reply, :ok, state}

      false ->
        ref = Process.monitor(pid)

        handlers =
          Map.update(state.event_handlers, event_type, [{pid, ref}], fn entries ->
            [{pid, ref} | entries]
          end)

        monitors = Map.put(state.monitors, ref, {pid, event_type})

        {:reply, :ok, %{state | event_handlers: handlers, monitors: monitors}}
    end
  end

  def handle_call({:unregister_handler, event_type, pid}, _from, state) do
    state = remove_handler(state, event_type, pid)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:libp2p_event, raw_event}, state) do
    case Event.from_raw(raw_event) do
      {:ok, event} ->
        event_type = event_type_for(event)
        dispatch_event(event_type, event, state)

      {:error, :unknown_event} ->
        Logger.debug("[ExLibp2p] Unknown event: #{inspect(raw_event)}")
    end

    {:noreply, state}
  end

  # Automatic cleanup when a monitored handler process dies
  def handle_info({:DOWN, ref, :process, dead_pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {{^dead_pid, event_type}, monitors} ->
        handlers =
          Map.update(state.event_handlers, event_type, [], &List.keydelete(&1, dead_pid, 0))

        {:noreply, %{state | event_handlers: handlers, monitors: monitors}}

      {nil, _monitors} ->
        {:noreply, state}
    end
  end

  def handle_info({:libp2p_noop}, state), do: {:noreply, state}
  def handle_info(:libp2p_noop, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) do
    Logger.info("[ExLibp2p] Node stopping (#{inspect(reason)}): #{state.peer_id}")
    state.native.stop_node(state.handle)
    :ok
  end

  # --- Private ---

  defp already_registered?(state, event_type, pid) do
    state.event_handlers
    |> Map.get(event_type, [])
    |> List.keymember?(pid, 0)
  end

  defp remove_handler(state, event_type, pid) do
    entries = Map.get(state.event_handlers, event_type, [])

    case List.keyfind(entries, pid, 0) do
      {^pid, ref} ->
        Process.demonitor(ref, [:flush])

        handlers =
          Map.put(state.event_handlers, event_type, List.keydelete(entries, pid, 0))

        %{state | event_handlers: handlers, monitors: Map.delete(state.monitors, ref)}

      nil ->
        state
    end
  end

  defp dispatch_event(event_type, event, state) do
    for {pid, _ref} <- Map.get(state.event_handlers, event_type, []) do
      send(pid, {:libp2p, event_type, event})
    end
  end

  # NIF fire-and-forget commands return {:ok, true} | {:error, reason}.
  # Normalize to :ok | {:error, reason} for Elixir callers.
  defp normalize_ok({:ok, _}), do: :ok
  defp normalize_ok({:error, _} = err), do: err
  defp normalize_ok(other), do: other

  defp event_type_for(%Event.ConnectionEstablished{}), do: :connection_established
  defp event_type_for(%Event.ConnectionClosed{}), do: :connection_closed
  defp event_type_for(%Event.NewListenAddr{}), do: :new_listen_addr
  defp event_type_for(%Event.GossipsubMessage{}), do: :gossipsub_message
  defp event_type_for(%Event.PeerDiscovered{}), do: :peer_discovered
  defp event_type_for(%Event.DHTQueryResult{}), do: :dht_query_result
  defp event_type_for(%Event.InboundRequest{}), do: :inbound_request
  defp event_type_for(%Event.OutboundResponse{}), do: :outbound_response
  defp event_type_for(%Event.NatStatusChanged{}), do: :nat_status_changed
  defp event_type_for(%Event.RelayReservationAccepted{}), do: :relay_reservation_accepted
  defp event_type_for(%Event.HolePunchOutcome{}), do: :hole_punch_outcome
  defp event_type_for(%Event.ExternalAddrConfirmed{}), do: :external_addr_confirmed
  defp event_type_for(%Event.DialFailure{}), do: :dial_failure

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), normalize_value(v)} end)
  end

  defp normalize_value(%{__struct__: _} = struct) do
    struct |> Map.from_struct() |> stringify_keys()
  end

  defp normalize_value(value), do: value
end
