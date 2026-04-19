defmodule ExLibp2p.Health do
  @moduledoc """
  Periodic health check for a libp2p node.

  Reports node health via telemetry and provides on-demand health status.
  Resilient to temporary node unresponsiveness — the health check continues
  running even if a single check fails.

  ## Usage

      {:ok, _} = ExLibp2p.Health.start_link(node: node, interval: 30_000)
      {:ok, status} = ExLibp2p.Health.check(health_pid)

  """

  use GenServer
  require Logger

  import ExLibp2p.Call, only: [safe_call: 2, safe_call: 3]

  @default_interval 30_000
  @check_timeout 10_000

  @doc "Starts a health check process linked to the caller."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Returns the current health status."
  @spec check(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def check(health), do: safe_call(health, :check)

  @impl true
  def init(opts) do
    node = Keyword.fetch!(opts, :node)
    interval = Keyword.get(opts, :interval, @default_interval)

    schedule_check(interval)
    {:ok, %{node: node, interval: interval, consecutive_failures: 0}}
  end

  @impl true
  def handle_call(:check, _from, state) do
    {:reply, collect_status(state.node), state}
  end

  @impl true
  def handle_info(:check, state) do
    state =
      case collect_status(state.node) do
        {:ok, status} ->
          :telemetry.execute(
            [:ex_libp2p, :health, :check],
            %{connected_peers: length(status.connected_peers)},
            %{peer_id: status.peer_id}
          )

          %{state | consecutive_failures: 0}

        {:error, reason} ->
          failures = state.consecutive_failures + 1

          Logger.warning(
            "[ExLibp2p.Health] Check failed (#{failures} consecutive): #{inspect(reason)}"
          )

          :telemetry.execute(
            [:ex_libp2p, :health, :check_failed],
            %{consecutive_failures: failures},
            %{reason: reason}
          )

          %{state | consecutive_failures: failures}
      end

    schedule_check(state.interval)
    {:noreply, state}
  end

  defp collect_status(node) do
    with {:ok, peer_id} <- safe_call(node, :peer_id, @check_timeout),
         {:ok, peers} <- safe_call(node, :connected_peers, @check_timeout),
         {:ok, addrs} <- safe_call(node, :listening_addrs, @check_timeout) do
      {:ok,
       %{
         peer_id: peer_id,
         connected_peers: peers,
         listening_addrs: addrs
       }}
    end
  end

  defp schedule_check(interval) do
    Process.send_after(self(), :check, interval)
  end
end
