defmodule ExLibp2p.Clock.SystemTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.Clock.System, as: SystemClock

  describe "monotonic_time/1" do
    test "returns an integer for :millisecond" do
      assert is_integer(SystemClock.monotonic_time(:millisecond))
    end

    test "returns an integer for :microsecond" do
      assert is_integer(SystemClock.monotonic_time(:microsecond))
    end

    test "returns an integer for :nanosecond" do
      assert is_integer(SystemClock.monotonic_time(:nanosecond))
    end

    test "successive calls are non-decreasing within the same unit" do
      a = SystemClock.monotonic_time(:millisecond)
      b = SystemClock.monotonic_time(:millisecond)
      assert b >= a
    end
  end
end
