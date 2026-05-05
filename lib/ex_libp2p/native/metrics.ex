defmodule ExLibp2p.Native.Metrics do
  @moduledoc """
  Behaviour for bandwidth and metrics operations.
  """

  @type handle :: reference()

  @callback bandwidth_stats(handle()) ::
              {:ok, non_neg_integer(), non_neg_integer()} | {:error, term()}

  @doc """
  Returns the Prometheus text-format encoding of the libp2p metrics
  registry. Includes bandwidth counters and any other metrics the swarm
  has registered. Suitable for direct exposure at a `/metrics` endpoint.
  """
  @callback prometheus_metrics(handle()) :: {:ok, String.t()} | {:error, term()}
end
