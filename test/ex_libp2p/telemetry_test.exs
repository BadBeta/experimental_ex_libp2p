defmodule ExLibp2p.TelemetryTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.Telemetry

  describe "event_names/0" do
    test "returns a non-empty list of telemetry event name lists, all prefixed with :ex_libp2p" do
      events = Telemetry.event_names()
      assert match?([_ | _], events)

      for event <- events do
        assert is_list(event)
        assert hd(event) == :ex_libp2p
      end
    end

    test "includes the span triplet for the dial operation" do
      events = Telemetry.event_names()
      assert [:ex_libp2p, :node, :dial, :start] in events
      assert [:ex_libp2p, :node, :dial, :stop] in events
      assert [:ex_libp2p, :node, :dial, :exception] in events
    end

    test "includes the gossipsub publish span triplet + subscribe/unsubscribe execute events" do
      events = Telemetry.event_names()
      assert [:ex_libp2p, :gossipsub, :publish, :start] in events
      assert [:ex_libp2p, :gossipsub, :publish, :stop] in events
      assert [:ex_libp2p, :gossipsub, :subscribe] in events
      assert [:ex_libp2p, :gossipsub, :unsubscribe] in events
    end

    test "includes health check events" do
      events = Telemetry.event_names()
      assert [:ex_libp2p, :health, :check] in events
      assert [:ex_libp2p, :health, :check_failed] in events
    end
  end

  describe "aspirational_event_names/0" do
    test "lists planned-but-not-yet-emitted events for forward-compat tooling" do
      events = Telemetry.aspirational_event_names()
      assert [:ex_libp2p, :connection, :established] in events
      assert [:ex_libp2p, :connection, :closed] in events
      assert [:ex_libp2p, :gossipsub, :message_received] in events
      assert [:ex_libp2p, :dht, :query_completed] in events
      assert [:ex_libp2p, :node, :started] in events
      assert [:ex_libp2p, :node, :stopped] in events
    end

    test "is disjoint from event_names/0 — no event appears in both lists" do
      stable = MapSet.new(Telemetry.event_names())
      aspirational = MapSet.new(Telemetry.aspirational_event_names())
      assert MapSet.intersection(stable, aspirational) |> MapSet.size() == 0
    end
  end
end
