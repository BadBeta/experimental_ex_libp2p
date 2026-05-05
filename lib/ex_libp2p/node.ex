defmodule ExLibp2p.Node do
  @moduledoc """
  GenServer wrapping a libp2p node.

  Manages the lifecycle of a libp2p node, dispatches network events through
  `ExLibp2p.Node.HandlerRegistry`, and provides the client API for all node
  operations.

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

  Handler processes are monitored by `HandlerRegistry` — when a handler exits,
  it is automatically removed. No dead PIDs accumulate over time.
  """

  use GenServer
  require Logger

  alias ExLibp2p.Multiaddr
  alias ExLibp2p.Node.{Config, Event, HandlerRegistry, NetworkOps, NifOps, Result}
  alias ExLibp2p.PeerId

  import ExLibp2p.Call, only: [safe_call: 2]

  @default_native Application.compile_env(:ex_libp2p, :native_module, ExLibp2p.Native.Nif)

  defstruct [:handle, :peer_id, :native, :dht_state_path, :dht_storage]

  @type t :: %__MODULE__{
          handle: reference() | nil,
          peer_id: PeerId.t() | nil,
          native: module(),
          # File path for DHT routing-table snapshot, or nil if persistence
          # is disabled. When set, the routing table is exported on
          # `terminate/2` and re-imported on `init/1` after `start_node`.
          dht_state_path: String.t() | nil,
          # Storage adapter (`ExLibp2p.Keypair.Storage` behaviour) used to
          # read/write the snapshot file. Resolved via
          # `ExLibp2p.Config.dht_state_storage/0`.
          dht_storage: module() | nil
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
  def peer_id(node), do: safe_call(node, :peer_id)

  @doc "Returns the list of currently connected peers."
  @spec connected_peers(GenServer.server()) :: {:ok, [PeerId.t()]} | {:error, term()}
  def connected_peers(node), do: safe_call(node, :connected_peers)

  @doc "Returns the addresses this node is listening on."
  @spec listening_addrs(GenServer.server()) :: {:ok, [String.t()]} | {:error, term()}
  def listening_addrs(node), do: safe_call(node, :listening_addrs)

  @doc """
  Dials a peer at the given multiaddr.

  The multiaddr should include a `/p2p/<peer_id>` component for direct dialing.
  """
  @spec dial(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def dial(node, addr) when is_binary(addr) do
    :telemetry.span([:ex_libp2p, :node, :dial], %{addr: addr}, fn ->
      result =
        case Multiaddr.new(addr) do
          {:ok, _} -> safe_call(node, {:dial, addr})
          {:error, _} -> {:error, :invalid_multiaddr}
        end

      {result, %{result: Result.tag(result)}}
    end)
  end

  @doc """
  Registers `pid` to receive events of `event_type` from `node`.

  Re-registering the same `{node, event_type, pid}` triple is a no-op. The
  registration is automatically cleaned up if `pid` exits — no stale PIDs
  accumulate.

  Event types: `:connection_established`, `:connection_closed`,
  `:new_listen_addr`, `:gossipsub_message`, `:peer_discovered`,
  `:dht_query_result`, `:inbound_request`, `:outbound_response`,
  `:nat_status_changed`, `:relay_reservation_accepted`, `:hole_punch_outcome`,
  `:external_addr_confirmed`, `:dial_failure`.
  """
  @spec register_handler(GenServer.server(), atom(), pid()) :: :ok | {:error, term()}
  def register_handler(node, event_type, pid \\ self()) do
    case GenServer.whereis(node) do
      nil -> {:error, :no_node}
      node_pid -> HandlerRegistry.register(HandlerRegistry, node_pid, event_type, pid)
    end
  end

  @doc "Unregisters `pid` from receiving `event_type` events from `node`. No-op if not registered."
  @spec unregister_handler(GenServer.server(), atom(), pid()) :: :ok | {:error, term()}
  def unregister_handler(node, event_type, pid \\ self()) do
    case GenServer.whereis(node) do
      nil -> {:error, :no_node}
      node_pid -> HandlerRegistry.unregister(HandlerRegistry, node_pid, event_type, pid)
    end
  end

  @doc "Stops the node gracefully."
  @spec stop(GenServer.server()) :: :ok
  def stop(node), do: GenServer.stop(node)

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    native = Keyword.get(opts, :native_module, @default_native)
    config_opts = Keyword.drop(opts, [:native_module])
    config = Config.new(config_opts)

    with {:ok, valid_config} <- Config.validate(config),
         config_map = Config.to_nif_map(valid_config),
         handle when is_reference(handle) <- start_node_safe(native, config_map),
         peer_id_str = native.get_peer_id(handle),
         {:ok, peer_id} <- PeerId.new(peer_id_str) do
      native.register_event_handler(handle, self())

      # graceful-shutdown checklist box. Re-import the persisted routing
      # table (if present) so a freshly-booted node skips rediscovery.
      # Failure is non-fatal: empty routing table is a valid state.
      dht_state_path = valid_config.discovery.dht_state_path
      dht_storage = ExLibp2p.Config.dht_state_storage()
      maybe_import_dht_state(native, handle, dht_state_path, dht_storage)

      Logger.info("[ExLibp2p] Node started: #{peer_id_str}")

      {:ok,
       %__MODULE__{
         handle: handle,
         peer_id: peer_id,
         native: native,
         dht_state_path: dht_state_path,
         dht_storage: dht_storage
       }}
    else
      {:error, reason} -> {:stop, {:failed_to_start, reason}}
    end
  end

  # Any failure (file not found, bad bytes, NIF rejection) is logged and
  # swallowed; the node continues with an empty routing table.
  defp maybe_import_dht_state(_native, _handle, nil, _storage), do: :ok

  defp maybe_import_dht_state(native, handle, path, storage) do
    case storage.read(path) do
      {:ok, bytes} ->
        case native.kad_import_routing_table(handle, bytes) do
          {:ok, count} ->
            Logger.info("[ExLibp2p] Imported #{count} DHT entries from #{path}")

          {:error, reason} ->
            Logger.warning(
              "[ExLibp2p] DHT state import failed (#{inspect(reason)}); continuing with empty routing table"
            )
        end

      {:error, :enoent} ->
        # First start with no prior snapshot — silently continue.
        :ok

      {:error, reason} ->
        Logger.warning(
          "[ExLibp2p] Could not read DHT state from #{path} (#{inspect(reason)}); continuing"
        )
    end
  end

  # `native.start_node/1` returns a bare reference on success (NifResult
  # special case unwraps `Ok`). On failure the real NIF raises
  # `ErlangError`; we catch and convert to the legacy `{:error, reason}`
  # shape so the `with` chain in `init/1` can short-circuit on either path.
  defp start_node_safe(native, config_map) do
    native.start_node(config_map)
  rescue
    e in ErlangError -> {:error, e.original}
  catch
    :error, reason -> {:error, reason}
  end

  # Thin dispatcher routing each call to NetworkOps / NifOps. Public API
  # shape unchanged — callers continue to send `:peer_id`, `{:dial, addr}`,
  # etc. without an envelope wrapper. NifOps owns the catch-all.
  @impl true
  def handle_call(call, from, state) do
    if NetworkOps.handles?(call) do
      NetworkOps.handle(call, from, state)
    else
      NifOps.handle(call, from, state)
    end
  end

  @impl true
  # and rendezvous (`rendezvous::client::Event::Discovered`) yield BATCHES of
  # peers in a single SwarmEvent, which the Rust side encodes as
  # `{:peers_discovered, [{:peer_discovered, ..., ...}, ...]}` when the batch
  # has 2+ entries. Fan the batch out into individual events so each
  # downstream handler sees one `:peer_discovered` per peer — without this,
  # Discovery callers register for `:peer_discovered` and see nothing when
  # mDNS finds multiple peers in one tick.
  def handle_info({:libp2p_event, {:peers_discovered, peer_list}}, state)
      when is_list(peer_list) do
    Enum.each(peer_list, fn raw -> dispatch_event(raw) end)
    {:noreply, state}
  end

  def handle_info({:libp2p_event, raw_event}, state) do
    dispatch_event(raw_event)
    {:noreply, state}
  end

  defp dispatch_event(raw_event) do
    case Event.from_raw(raw_event) do
      {:ok, event} ->
        HandlerRegistry.dispatch(HandlerRegistry, self(), event_type_for(event), event)

      {:error, :unknown_event} ->
        Logger.debug("[ExLibp2p] Unknown event: #{inspect(raw_event)}")
    end
  end

  def handle_info({:libp2p_noop}, state), do: {:noreply, state}
  def handle_info(:libp2p_noop, state), do: {:noreply, state}

  def handle_info(msg, state) do
    Logger.warning("[ExLibp2p.Node] Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # (opaque, not useful in dumps). Handler bookkeeping lives in HandlerRegistry now,
  # so Node's status output is just identity + native module.
  @impl true
  def format_status(%{state: state} = status) when is_map(state) do
    summary = %{
      handle: :redacted_handle,
      peer_id: state.peer_id,
      native: state.native
    }

    %{status | state: summary}
  end

  def format_status(status), do: status

  @impl true
  def terminate(reason, state) do
    Logger.info("[ExLibp2p] Node stopping (#{inspect(reason)}): #{state.peer_id}")
    # Drop subscriptions held against this node so a restarted Node with the
    # same name doesn't inherit stale registrations under a different pid.
    HandlerRegistry.cleanup_node(HandlerRegistry, self())

    # the routing table BEFORE `stop_node`, so the swarm task is still
    # alive and can answer the export query. Best-effort: a write failure
    # is logged, not propagated, so shutdown completes cleanly.
    maybe_export_dht_state(state)

    state.native.stop_node(state.handle)
    :ok
  end

  defp maybe_export_dht_state(%__MODULE__{dht_state_path: nil}), do: :ok

  defp maybe_export_dht_state(%__MODULE__{
         native: native,
         handle: handle,
         dht_state_path: path,
         dht_storage: storage
       }) do
    case native.kad_export_routing_table(handle) do
      {:ok, bytes} ->
        case storage.write(path, bytes) do
          :ok ->
            Logger.debug("[ExLibp2p] DHT state exported (#{byte_size(bytes)} bytes) → #{path}")

          {:error, reason} ->
            Logger.warning(
              "[ExLibp2p] Could not write DHT state to #{path} (#{inspect(reason)}); shutdown continues"
            )
        end

      {:error, reason} ->
        Logger.warning(
          "[ExLibp2p] DHT state export failed (#{inspect(reason)}); shutdown continues"
        )
    end
  end

  # --- Private ---

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
end
