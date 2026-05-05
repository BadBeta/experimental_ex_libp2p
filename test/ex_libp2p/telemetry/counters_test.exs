defmodule ExLibp2p.Telemetry.CountersTest do
  use ExUnit.Case, async: false
  # async: false — Counters is a singleton subscriber attached to globally-named
  # telemetry events. Tests share the same handler.

  alias ExLibp2p.Telemetry.Counters

  setup do
    # Use a unique name per test so async-false tests don't conflict on the
    # default singleton registration. start_supervised! handles teardown.
    name = :"counters_#{System.unique_integer([:positive])}"
    pid = start_supervised!({Counters, name: name})
    %{counters: pid}
  end

  describe "event recording" do
    test "increments :ok counter when a Gossipsub publish span succeeds",
         %{counters: counters} do
      :telemetry.execute(
        [:ex_libp2p, :gossipsub, :publish, :stop],
        %{duration: 1_000},
        %{topic: "alpha", result: :ok}
      )

      Counters.sync(counters)

      snapshot = Counters.snapshot(counters)
      assert snapshot[{[:ex_libp2p, :gossipsub, :publish, :stop], :ok}] == 1
    end

    test "increments :error counter when the same span returns :error",
         %{counters: counters} do
      :telemetry.execute(
        [:ex_libp2p, :node, :dial, :stop],
        %{duration: 1_000},
        %{addr: "/ip4/1.2.3.4/tcp/9", result: :error}
      )

      Counters.sync(counters)

      snapshot = Counters.snapshot(counters)
      assert snapshot[{[:ex_libp2p, :node, :dial, :stop], :error}] == 1
    end

    test "counts independent of the metadata when result is missing",
         %{counters: counters} do
      :telemetry.execute(
        [:ex_libp2p, :health, :check],
        %{duration: 1_000},
        %{}
      )

      Counters.sync(counters)
      snapshot = Counters.snapshot(counters)
      # The :unknown bucket catches metadata without a :result tag.
      assert snapshot[{[:ex_libp2p, :health, :check], :unknown}] == 1
    end
  end

  describe "render_prometheus/1" do
    test "renders snapshot as Prometheus text format", %{counters: counters} do
      :telemetry.execute([:ex_libp2p, :gossipsub, :publish, :stop], %{duration: 1}, %{result: :ok})
      :telemetry.execute([:ex_libp2p, :gossipsub, :publish, :stop], %{duration: 1}, %{result: :ok})
      :telemetry.execute([:ex_libp2p, :node, :dial, :stop], %{duration: 1}, %{result: :error})

      Counters.sync(counters)

      text = Counters.render_prometheus(counters)

      # # HELP and # TYPE lines per metric family
      assert text =~ "# TYPE ex_libp2p_gossipsub_publish_stop_total counter"
      assert text =~ ~r/ex_libp2p_gossipsub_publish_stop_total\{result="ok"\} 2/
      assert text =~ ~r/ex_libp2p_node_dial_stop_total\{result="error"\} 1/
    end

    test "returns valid (empty) Prometheus text when no events recorded",
         %{counters: counters} do
      text = Counters.render_prometheus(counters)
      # Renders a comment header even with no data, so scrapes don't 404.
      assert text =~ "# ExLibp2p telemetry counters"
    end
  end

  describe "reset/1" do
    test "clears all counters", %{counters: counters} do
      :telemetry.execute([:ex_libp2p, :health, :check], %{}, %{result: :ok})
      Counters.sync(counters)
      assert Counters.snapshot(counters) != %{}

      :ok = Counters.reset(counters)

      assert Counters.snapshot(counters) == %{}
    end
  end
end
