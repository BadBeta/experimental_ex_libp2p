defmodule ExLibp2p.Metrics do
  @moduledoc """
  Network metrics and observability.

  Provides bandwidth statistics and integrates with `ExLibp2p.Telemetry`
  for Prometheus/StatsD reporting.

  ## Usage

      {:ok, %{bytes_in: in, bytes_out: out}} = ExLibp2p.Metrics.bandwidth(node)

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
end
