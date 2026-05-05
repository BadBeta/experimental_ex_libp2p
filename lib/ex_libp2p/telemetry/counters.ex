defmodule ExLibp2p.Telemetry.Counters do
  @moduledoc """
  In-memory telemetry counter store with Prometheus text-format rendering.

  Subscribes to the events listed in `ExLibp2p.Telemetry.event_names/0` and
  increments a counter per `{event, result_tag}` pair. The `result_tag` comes
  from the `:result` metadata key (`:ok` / `:error` / `:unknown`); span events
  carry it explicitly via `ExLibp2p.Node.Result.tag/1`.

  ## Why no Prometheus client dep

  This module deliberately avoids `prometheus_ex` / `peep` /
  `telemetry_metrics_prometheus` so the library has zero observability deps.
  Library consumers wanting full Prometheus integration (histograms, gauges,
  Plug endpoint, scrape protocol) plug their own renderer over
  `snapshot/1` — the data is exposed; the format is up to them.

  ## Usage

      # Render Prometheus text for a `/metrics` endpoint:
      Plug.Conn.send_resp(conn, 200,
        ExLibp2p.Telemetry.Counters.render_prometheus())
  """

  use GenServer
  require Logger

  alias ExLibp2p.Telemetry

  defstruct counts: %{}, attached?: false

  @type result_tag :: :ok | :error | :unknown
  @type counter_key :: {event :: [atom()], result_tag()}
  @type snapshot :: %{counter_key() => non_neg_integer()}

  # --- Client API ---

  @doc "Starts the counter store under a supervisor."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, init_opts} = Keyword.split(opts, [:name])
    name = Keyword.get(gen_opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, init_opts, name: name)
  end

  @doc "Returns a map of all counter values."
  @spec snapshot(GenServer.server()) :: snapshot()
  def snapshot(counters \\ __MODULE__), do: GenServer.call(counters, :snapshot)

  @doc """
  Renders the current counters as Prometheus text format.

  Output is `# HELP` / `# TYPE` / metric-line per `{event, result}` pair.
  Always returns at least the comment header so empty scrapes don't 404.
  """
  @spec render_prometheus(GenServer.server()) :: String.t()
  def render_prometheus(counters \\ __MODULE__) do
    counters |> snapshot() |> do_render_prometheus()
  end

  @doc "Clears all counters. Useful in tests."
  @spec reset(GenServer.server()) :: :ok
  def reset(counters \\ __MODULE__), do: GenServer.call(counters, :reset)

  @doc """
  Synchronizes the counter store with prior telemetry events.

  Telemetry handlers run in the calling process synchronously, so this is
  effectively a no-op call to ensure prior `GenServer.cast` events have been
  drained. Used in tests.
  """
  @spec sync(GenServer.server()) :: :ok
  def sync(counters \\ __MODULE__), do: GenServer.call(counters, :sync)

  # --- Server ---

  @impl true
  def init(_opts) do
    handler_id = "ex_libp2p_counters_#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        Telemetry.event_names(),
        &__MODULE__.handle_event/4,
        %{counters: self()}
      )

    Process.flag(:trap_exit, true)
    {:ok, %__MODULE__{attached?: true, counts: %{handler_id: handler_id}}}
  end

  @doc false
  # Telemetry handler — runs in the caller's process, casts to the GenServer
  # so the increment is serialized but the caller is not blocked.
  def handle_event(event, _measurements, metadata, %{counters: counters}) do
    result_tag =
      case Map.get(metadata, :result) do
        :ok -> :ok
        :error -> :error
        _ -> :unknown
      end

    GenServer.cast(counters, {:increment, event, result_tag})
  end

  @impl true
  def handle_cast({:increment, event, result_tag}, state) do
    counts =
      Map.update(state.counts, {event, result_tag}, 1, &(&1 + 1))

    {:noreply, %{state | counts: counts}}
  end

  def handle_cast(unknown, state) do
    Logger.warning("[ExLibp2p.Telemetry.Counters] Unknown cast: #{inspect(unknown)}")
    {:noreply, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    user_counts =
      state.counts
      |> Enum.reject(fn {k, _v} -> k == :handler_id end)
      |> Map.new()

    {:reply, user_counts, state}
  end

  def handle_call(:reset, _from, state) do
    handler_id = Map.get(state.counts, :handler_id)
    {:reply, :ok, %{state | counts: %{handler_id: handler_id}}}
  end

  def handle_call(:sync, _from, state), do: {:reply, :ok, state}

  def handle_call(unknown, _from, state) do
    Logger.warning("[ExLibp2p.Telemetry.Counters] Unknown call: #{inspect(unknown)}")
    {:reply, {:error, :unknown_call}, state}
  end

  @impl true
  def terminate(_reason, %{counts: %{handler_id: handler_id}}) when is_binary(handler_id) do
    :telemetry.detach(handler_id)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  # production; summarize as count of distinct counters in status output.
  @impl true
  def format_status(%{state: %__MODULE__{} = state} = status) do
    summary = %{
      attached?: state.attached?,
      counter_count: state.counts |> Map.delete(:handler_id) |> map_size()
    }

    %{status | state: summary}
  end

  def format_status(status), do: status

  # --- Private ---

  defp do_render_prometheus(snapshot) when map_size(snapshot) == 0 do
    "# ExLibp2p telemetry counters (no events recorded yet)\n"
  end

  defp do_render_prometheus(snapshot) do
    snapshot
    |> Enum.group_by(fn {{event, _result}, _count} -> event end)
    |> Enum.sort_by(fn {event, _entries} -> event end)
    |> Enum.flat_map(&render_metric_family/1)
    |> IO.iodata_to_binary()
  end

  defp render_metric_family({event, entries}) do
    metric_name = metric_name_for(event)

    header =
      [
        "# HELP ",
        metric_name,
        "_total Number of [",
        Enum.map_join(event, ", ", &Atom.to_string/1),
        "] events fired, partitioned by result.\n",
        "# TYPE ",
        metric_name,
        "_total counter\n"
      ]

    body =
      entries
      |> Enum.sort_by(fn {{_event, result}, _count} -> result end)
      |> Enum.map(fn {{_event, result}, count} ->
        [
          metric_name,
          "_total{result=\"",
          Atom.to_string(result),
          "\"} ",
          Integer.to_string(count),
          "\n"
        ]
      end)

    [header, body, "\n"]
  end

  defp metric_name_for(event) do
    event |> Enum.map_join("_", &Atom.to_string/1)
  end
end
