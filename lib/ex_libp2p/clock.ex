defmodule ExLibp2p.Clock do
  @moduledoc """
  Behaviour for monotonic-time sources.

  Abstracts `System.monotonic_time/1` so callers (currently
  `ExLibp2p.OTP.TaskTracker`) can be tested with a controllable clock.
  Mox-mockable for fine-grained scheduling tests.

  ## Implementations

    * `ExLibp2p.Clock.System` — wraps `System.monotonic_time/1` (production default).
    * `ExLibp2p.Clock.Mock` — auto-generated via Mox in `test/test_helper.exs`.

  ## Configuration

      # config/config.exs (production default — implicit)
      config :ex_libp2p, ExLibp2p.OTP.TaskTracker, clock: ExLibp2p.Clock.System

      # config/test.exs (Mox swap)
      config :ex_libp2p, ExLibp2p.OTP.TaskTracker, clock: ExLibp2p.Clock.Mock

  Resolved at runtime via `ExLibp2p.Config.task_tracker_clock/0`.
  """

  @typedoc "Time unit accepted by `monotonic_time/1`."
  @type unit :: :millisecond | :microsecond | :nanosecond

  @doc """
  Returns a monotonically-non-decreasing integer in the requested unit.

  Two successive calls within the same unit MUST satisfy `b >= a`. The actual
  value has no defined epoch — it's only useful for measuring elapsed time.
  """
  @callback monotonic_time(unit()) :: integer()
end
