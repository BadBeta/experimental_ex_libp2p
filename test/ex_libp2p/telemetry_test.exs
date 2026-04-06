defmodule ExLibp2p.TelemetryTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.Telemetry

  describe "event_names/0" do
    test "returns a list of telemetry event name lists" do
      events = Telemetry.event_names()
      assert is_list(events)
      assert length(events) > 0

      for event <- events do
        assert is_list(event)
        assert hd(event) == :ex_libp2p
      end
    end
  end

  describe "events" do
    test "connection events are defined" do
      events = Telemetry.event_names()
      assert [:ex_libp2p, :connection, :established] in events
      assert [:ex_libp2p, :connection, :closed] in events
    end

    test "gossipsub events are defined" do
      events = Telemetry.event_names()
      assert [:ex_libp2p, :gossipsub, :message_received] in events
      assert [:ex_libp2p, :gossipsub, :message_published] in events
    end

    test "dht events are defined" do
      events = Telemetry.event_names()
      assert [:ex_libp2p, :dht, :query_completed] in events
    end

    test "health events are defined" do
      events = Telemetry.event_names()
      assert [:ex_libp2p, :health, :check] in events
      assert [:ex_libp2p, :health, :check_failed] in events
    end

    test "node events are defined" do
      events = Telemetry.event_names()
      assert [:ex_libp2p, :node, :started] in events
      assert [:ex_libp2p, :node, :stopped] in events
    end
  end
end
