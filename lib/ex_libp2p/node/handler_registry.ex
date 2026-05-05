defmodule ExLibp2p.Node.HandlerRegistry do
  @moduledoc """
  Subscriber registry for libp2p node events.

  When `ExLibp2p.Node` receives a libp2p event from the NIF, it dispatches the
  event to every process that has registered for that `{node, event_type}`
  pair. The registry is keyed by `{node_pid, event_type}` so multiple Node
  instances can share a single registry without cross-talk.

  ## Lifecycle

  - Registered with the application supervision tree (singleton, `name:
    ExLibp2p.Node.HandlerRegistry`) and started **before** `ExLibp2p.Node` so
    nodes can dispatch into it from their `handle_info` clauses.
  - When a registered subscriber process dies, the registry receives the
    `:DOWN` and removes the subscription automatically.
  - When a Node terminates, it calls `cleanup_node/2` from `terminate/2` to
    remove all subscriptions for itself.

  ## Why a separate module

  Six sibling contexts (`Discovery`, `DHT`, `Relay`, `Rendezvous`,
  `RequestResponse`, `OTP.TaskTracker`) all converge on the registration
  surface. When many callers depend on one function, that function deserves
  to be a sibling boundary. Extracting also removes the `event_handlers` and
  `monitors` maps from `ExLibp2p.Node`'s state, keeping the GenServer focused
  on driving the NIF event loop.
  """

  use GenServer
  require Logger

  defstruct subscriptions: %{}, monitors: %{}

  @type state :: %__MODULE__{
          # %{{node_pid, event_type} => [{subscriber_pid, monitor_ref}]}
          subscriptions: %{{pid(), atom()} => [{pid(), reference()}]},
          # %{monitor_ref => {subscriber_pid, node_pid, event_type}} — reverse index for :DOWN
          monitors: %{reference() => {pid(), pid(), atom()}}
        }

  # --- Client API ---

  @doc "Starts the handler registry."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, init_opts} = Keyword.split(opts, [:name])
    name = Keyword.get(gen_opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, init_opts, name: name)
  end

  @doc """
  Registers `pid` to receive events of `event_type` from `node`.

  Idempotent: re-registering the same `{node, event_type, pid}` is a no-op.
  Returns `:ok` either way.
  """
  @spec register(GenServer.server(), pid(), atom(), pid()) :: :ok
  def register(registry, node, event_type, pid)
      when is_pid(node) and is_atom(event_type) and is_pid(pid) do
    GenServer.call(registry, {:register, node, event_type, pid})
  end

  @doc "Unregisters `pid` from `event_type` events for `node`. No-op if not registered."
  @spec unregister(GenServer.server(), pid(), atom(), pid()) :: :ok
  def unregister(registry, node, event_type, pid)
      when is_pid(node) and is_atom(event_type) and is_pid(pid) do
    GenServer.call(registry, {:unregister, node, event_type, pid})
  end

  @doc """
  Dispatches `event` to every subscriber of `{node, event_type}`.

  Sends `{:libp2p, event_type, event}` to each subscriber. Returns `:ok`
  immediately (cast — the caller is not blocked by subscriber delivery).
  """
  @spec dispatch(GenServer.server(), pid(), atom(), term()) :: :ok
  def dispatch(registry, node, event_type, event)
      when is_pid(node) and is_atom(event_type) do
    GenServer.cast(registry, {:dispatch, node, event_type, event})
  end

  @doc "Returns the subscriber count for `{node, event_type}` (observability/tests)."
  @spec count(GenServer.server(), pid(), atom()) :: non_neg_integer()
  def count(registry, node, event_type) when is_pid(node) and is_atom(event_type) do
    GenServer.call(registry, {:count, node, event_type})
  end

  @doc "Removes all subscriptions for `node`. Called from `Node.terminate/2`."
  @spec cleanup_node(GenServer.server(), pid()) :: :ok
  def cleanup_node(registry, node) when is_pid(node) do
    GenServer.call(registry, {:cleanup_node, node})
  end

  @doc """
  Synchronizes the registry by issuing a no-op call.

  Useful in tests to wait for prior `cast/3` dispatches and `:DOWN` cleanup
  messages to be processed before asserting state.
  """
  @spec sync(GenServer.server()) :: :ok
  def sync(registry), do: GenServer.call(registry, :sync)

  # --- Server Callbacks ---

  @impl true
  def init(_opts), do: {:ok, %__MODULE__{}}

  @impl true
  def handle_call({:register, node, event_type, pid}, _from, state) do
    key = {node, event_type}

    case already_registered?(state, key, pid) do
      true ->
        {:reply, :ok, state}

      false ->
        ref = Process.monitor(pid)

        subscriptions =
          Map.update(state.subscriptions, key, [{pid, ref}], fn entries ->
            [{pid, ref} | entries]
          end)

        monitors = Map.put(state.monitors, ref, {pid, node, event_type})
        {:reply, :ok, %{state | subscriptions: subscriptions, monitors: monitors}}
    end
  end

  def handle_call({:unregister, node, event_type, pid}, _from, state) do
    {:reply, :ok, remove_subscription(state, {node, event_type}, pid)}
  end

  def handle_call({:count, node, event_type}, _from, state) do
    count = state.subscriptions |> Map.get({node, event_type}, []) |> length()
    {:reply, count, state}
  end

  def handle_call({:cleanup_node, node}, _from, state) do
    {:reply, :ok, remove_all_for_node(state, node)}
  end

  def handle_call(:sync, _from, state), do: {:reply, :ok, state}

  def handle_call(unknown, _from, state) do
    Logger.warning("[ExLibp2p.Node.HandlerRegistry] Unknown call: #{inspect(unknown)}")
    {:reply, {:error, :unknown_call}, state}
  end

  @impl true
  def handle_cast({:dispatch, node, event_type, event}, state) do
    for {pid, _ref} <- Map.get(state.subscriptions, {node, event_type}, []) do
      send(pid, {:libp2p, event_type, event})
    end

    {:noreply, state}
  end

  def handle_cast(unknown, state) do
    Logger.warning("[ExLibp2p.Node.HandlerRegistry] Unknown cast: #{inspect(unknown)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, dead_pid, _reason}, state) do
    {:noreply, remove_dead_subscriber(state, ref, dead_pid)}
  end

  def handle_info(msg, state) do
    Logger.debug("[ExLibp2p.Node.HandlerRegistry] Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # counts so production status dumps don't print large maps.
  @impl true
  def format_status(%{state: %__MODULE__{} = state} = status) do
    summary = %{
      subscriptions: map_size(state.subscriptions),
      monitors: map_size(state.monitors)
    }

    %{status | state: summary}
  end

  def format_status(status), do: status

  # --- Private ---

  defp already_registered?(state, key, pid) do
    state.subscriptions
    |> Map.get(key, [])
    |> List.keymember?(pid, 0)
  end

  defp remove_subscription(state, key, pid) do
    entries = Map.get(state.subscriptions, key, [])

    case List.keyfind(entries, pid, 0) do
      {^pid, ref} ->
        Process.demonitor(ref, [:flush])

        subscriptions =
          case List.keydelete(entries, pid, 0) do
            [] -> Map.delete(state.subscriptions, key)
            remaining -> Map.put(state.subscriptions, key, remaining)
          end

        %{state | subscriptions: subscriptions, monitors: Map.delete(state.monitors, ref)}

      nil ->
        state
    end
  end

  defp remove_dead_subscriber(state, ref, dead_pid) do
    case Map.pop(state.monitors, ref) do
      {{^dead_pid, node, event_type}, monitors} ->
        key = {node, event_type}

        subscriptions =
          case Map.get(state.subscriptions, key, []) |> List.keydelete(dead_pid, 0) do
            [] -> Map.delete(state.subscriptions, key)
            remaining -> Map.put(state.subscriptions, key, remaining)
          end

        %{state | subscriptions: subscriptions, monitors: monitors}

      {nil, _monitors} ->
        state
    end
  end

  defp remove_all_for_node(state, node) do
    {keys_to_drop, refs_to_drop} =
      Enum.reduce(state.subscriptions, {[], []}, fn
        {{^node, _event_type} = key, entries}, {keys_acc, refs_acc} ->
          refs = Enum.map(entries, fn {_pid, ref} -> ref end)
          {[key | keys_acc], refs ++ refs_acc}

        _entry, acc ->
          acc
      end)

    Enum.each(refs_to_drop, &Process.demonitor(&1, [:flush]))

    %{
      state
      | subscriptions: Map.drop(state.subscriptions, keys_to_drop),
        monitors: Map.drop(state.monitors, refs_to_drop)
    }
  end
end
