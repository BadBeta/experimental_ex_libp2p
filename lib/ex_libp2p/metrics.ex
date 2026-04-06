defmodule ExLibp2p.Metrics do
  @moduledoc """
  Network metrics and observability.

  Provides bandwidth statistics and integrates with `ExLibp2p.Telemetry`
  for Prometheus/StatsD reporting.

  ## Usage

      {:ok, %{bytes_in: in, bytes_out: out}} = ExLibp2p.Metrics.bandwidth(node)

  """

  alias ExLibp2p.Node

  @doc """
  Returns the total bandwidth consumed by the node.

  Returns `{:ok, %{bytes_in: integer, bytes_out: integer}}`.
  """
  @spec bandwidth(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def bandwidth(node) do
    with {:ok, bytes_in, bytes_out} <- Node.bandwidth_stats(node) do
      {:ok, %{bytes_in: bytes_in, bytes_out: bytes_out}}
    end
  end
end
