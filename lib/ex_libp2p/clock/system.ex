defmodule ExLibp2p.Clock.System do
  @moduledoc """
  Production implementation of `ExLibp2p.Clock` backed by `System.monotonic_time/1`.

  Pure passthrough — added solely so tests can swap in `ExLibp2p.Clock.Mock`
  via Mox for time-sensitive scheduling tests.
  """

  @behaviour ExLibp2p.Clock

  @impl true
  def monotonic_time(unit), do: System.monotonic_time(unit)
end
