defmodule ExLibp2p.Metrics do
  @moduledoc """
  Network metrics and observability.

  Provides bandwidth statistics and a Prometheus text-format scrape suitable
  for direct exposure at a `/metrics` endpoint, plus integration with
  `ExLibp2p.Telemetry` for Prometheus/StatsD reporting.

  ## Usage

      {:ok, %{bytes_in: in, bytes_out: out}} = ExLibp2p.Metrics.bandwidth(node)

      # Full Prometheus text scrape (for /metrics endpoints):
      {:ok, text} = ExLibp2p.Metrics.prometheus_scrape(node)

  """

  import ExLibp2p.Call, only: [safe_call: 2]

  @doc """
  Returns the total bandwidth consumed by the node.

  Returns `{:ok, %{bytes_in: integer, bytes_out: integer}}`.
  """
  @spec bandwidth(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def bandwidth(node) do
    case safe_call(node, :bandwidth_stats) do
      {:ok, bytes_in, bytes_out} -> {:ok, %{bytes_in: bytes_in, bytes_out: bytes_out}}
      {:error, _} = error -> error
    end
  end

  @doc """
  Returns the libp2p metrics registry encoded as Prometheus text format.

  The Rust-side `SwarmBuilder::with_bandwidth_metrics` registers bandwidth
  counters into a `prometheus_client::Registry`; this function scrapes
  that registry. The string can be served directly at a `/metrics` HTTP
  endpoint or fed into a metrics aggregator.
  """
  @spec prometheus_scrape(GenServer.server()) :: {:ok, String.t()} | {:error, term()}
  def prometheus_scrape(node), do: safe_call(node, :prometheus_metrics)
end
