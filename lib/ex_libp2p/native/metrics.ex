defmodule ExLibp2p.Native.Metrics do
  @moduledoc """
  Behaviour for bandwidth and metrics operations.
  """

  @type handle :: reference()

  @callback bandwidth_stats(handle()) ::
              {:ok, non_neg_integer(), non_neg_integer()} | {:error, atom()}
end
