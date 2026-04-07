defmodule ExLibp2p.OTP.TaskTracker do
  @moduledoc """
  Tracks dispatched tasks and detects orphaned work when peers disappear.

  When work is dispatched to a remote peer via `ExLibp2p.OTP.Distribution`, the
  task tracker records it. If the peer disconnects before the task completes,
  subscribers are notified with the list of orphaned tasks so they can be
  re-dispatched to another peer.

  ## Usage

      # Start the tracker
      {:ok, tracker} = ExLibp2p.OTP.TaskTracker.start_link(node: node)

      # Subscribe to peer-loss notifications
      ExLibp2p.OTP.TaskTracker.subscribe(tracker)

      # Dispatch work (records the task)
      {:ok, task_id} = ExLibp2p.OTP.TaskTracker.dispatch(tracker, peer_id, :my_worker, {:process, data})

      # When work completes, mark it done
      :ok = ExLibp2p.OTP.TaskTracker.complete(tracker, task_id)

      # If the peer disappears before completion, you receive:
      # {:task_tracker, :peer_lost, peer_id, [%TaskTracker.Task{status: {:failed, :peer_lost}}]}

  ## Task Lifecycle

      dispatch/4 → :pending
                      ↓
            complete/2 → :completed
            fail/3     → {:failed, reason}
            peer loss  → {:failed, :peer_lost}   (automatic)

  ## Cleanup

  Completed and failed tasks accumulate in memory. Call `cleanup/1` periodically
  to remove them, or they will be cleaned up when the tracker is stopped.
  """

  use GenServer
  require Logger

  alias ExLibp2p.{Node, PeerId}
  alias ExLibp2p.Node.Event

  defmodule Task do
    @moduledoc "A tracked remote task."
    @enforce_keys [:id, :peer_id, :target, :message]
    defstruct [:id, :peer_id, :target, :message, :dispatched_at, status: :pending]

    @type t :: %__MODULE__{
            id: String.t(),
            peer_id: PeerId.t(),
            target: atom(),
            message: term(),
            status: :pending | :completed | {:failed, term()},
            dispatched_at: integer()
          }
  end

  # State: tasks map + subscribers + counter
  defstruct tasks: %{}, subscribers: [], counter: 0

  @doc "Starts a task tracker linked to the caller."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {gen_opts, tracker_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, tracker_opts, gen_opts)
  end

  @doc """
  Records a dispatched task. Returns `{:ok, task_id}`.

  Does NOT send the actual message — the caller is responsible for
  dispatching via `ExLibp2p.OTP.Distribution.call/5` or similar.
  """
  @spec dispatch(GenServer.server(), PeerId.t(), atom(), term()) :: {:ok, String.t()}
  def dispatch(tracker, %PeerId{} = peer_id, target, message) when is_atom(target) do
    GenServer.call(tracker, {:dispatch, peer_id, target, message})
  end

  @doc "Marks a task as completed."
  @spec complete(GenServer.server(), String.t()) :: :ok | {:error, :not_found}
  def complete(tracker, task_id), do: GenServer.call(tracker, {:complete, task_id})

  @doc "Marks a task as failed with the given reason."
  @spec fail(GenServer.server(), String.t(), term()) :: :ok | {:error, :not_found}
  def fail(tracker, task_id, reason), do: GenServer.call(tracker, {:fail, task_id, reason})

  @doc "Returns a tracked task by ID."
  @spec get(GenServer.server(), String.t()) :: {:ok, Task.t()} | {:error, :not_found}
  def get(tracker, task_id), do: GenServer.call(tracker, {:get, task_id})

  @doc "Returns all pending tasks for a specific peer."
  @spec pending_for_peer(GenServer.server(), PeerId.t()) :: [Task.t()]
  def pending_for_peer(tracker, %PeerId{} = peer_id) do
    GenServer.call(tracker, {:pending_for_peer, peer_id})
  end

  @doc "Returns all pending tasks across all peers."
  @spec all_pending(GenServer.server()) :: [Task.t()]
  def all_pending(tracker), do: GenServer.call(tracker, :all_pending)

  @doc """
  Subscribes the calling process to peer-loss notifications.

  When a peer with pending tasks disconnects, subscribers receive:
  `{:task_tracker, :peer_lost, peer_id, orphaned_tasks}`
  """
  @spec subscribe(GenServer.server()) :: :ok
  def subscribe(tracker), do: GenServer.call(tracker, {:subscribe, self()})

  @doc "Removes completed and failed tasks. Returns the number removed."
  @spec cleanup(GenServer.server()) :: non_neg_integer()
  def cleanup(tracker), do: GenServer.call(tracker, :cleanup)

  # --- Server ---

  @impl true
  def init(opts) do
    node = Keyword.fetch!(opts, :node)
    Node.register_handler(node, :connection_closed, self())

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:dispatch, peer_id, target, message}, _from, state) do
    id = "task-#{state.counter + 1}"

    task = %Task{
      id: id,
      peer_id: peer_id,
      target: target,
      message: message,
      dispatched_at: System.monotonic_time(:millisecond)
    }

    state = %{state | tasks: Map.put(state.tasks, id, task), counter: state.counter + 1}
    {:reply, {:ok, id}, state}
  end

  def handle_call({:complete, task_id}, _from, state) do
    update_task_status(state, task_id, :completed)
  end

  def handle_call({:fail, task_id, reason}, _from, state) do
    update_task_status(state, task_id, {:failed, reason})
  end

  def handle_call({:get, task_id}, _from, state) do
    case Map.fetch(state.tasks, task_id) do
      {:ok, task} -> {:reply, {:ok, task}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:pending_for_peer, peer_id}, _from, state) do
    {:reply, pending_tasks(state, fn t -> t.peer_id == peer_id end), state}
  end

  def handle_call(:all_pending, _from, state) do
    {:reply, pending_tasks(state, fn _ -> true end), state}
  end

  def handle_call({:subscribe, pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: [pid | state.subscribers]}}
  end

  def handle_call(:cleanup, _from, state) do
    {removed, kept} =
      Map.split_with(state.tasks, fn {_id, task} ->
        task.status != :pending
      end)

    {:reply, map_size(removed), %{state | tasks: kept}}
  end

  @impl true
  def handle_info(
        {:libp2p, :connection_closed,
         %Event.ConnectionClosed{peer_id: peer_id, num_established: 0}},
        state
      ) do
    # Last connection to this peer closed — find and mark orphaned tasks in one pass
    {updated_tasks, orphaned} =
      Enum.reduce(state.tasks, {state.tasks, []}, fn
        {id, %{status: :pending, peer_id: ^peer_id} = task}, {tasks_acc, orphaned_acc} ->
          failed = %{task | status: {:failed, :peer_lost}}
          {Map.put(tasks_acc, id, failed), [failed | orphaned_acc]}

        _entry, acc ->
          acc
      end)

    case orphaned do
      [] ->
        {:noreply, state}

      _ ->
        for pid <- state.subscribers, Process.alive?(pid) do
          Kernel.send(pid, {:task_tracker, :peer_lost, peer_id, orphaned})
        end

        Logger.warning(
          "[ExLibp2p.OTP.TaskTracker] Peer #{peer_id} lost with #{length(orphaned)} pending tasks"
        )

        {:noreply, %{state | tasks: updated_tasks}}
    end
  end

  # Ignore connection_closed events where num_established > 0 (still connected)
  def handle_info({:libp2p, :connection_closed, _}, state), do: {:noreply, state}

  def handle_info(msg, state) do
    Logger.debug("[ExLibp2p.OTP.TaskTracker] Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # --- Private helpers ---

  defp update_task_status(state, task_id, new_status) do
    case Map.fetch(state.tasks, task_id) do
      {:ok, task} ->
        tasks = Map.put(state.tasks, task_id, %{task | status: new_status})
        {:reply, :ok, %{state | tasks: tasks}}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  defp pending_tasks(state, extra_filter) do
    for {_id, %{status: :pending} = task} <- state.tasks, extra_filter.(task), do: task
  end
end
