defmodule ExLibp2p.Node.EventTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.Node.Event
  alias ExLibp2p.PeerId

  describe "ConnectionEstablished" do
    test "creates event with peer_id" do
      event = %Event.ConnectionEstablished{
        peer_id: PeerId.new!("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"),
        num_established: 1,
        endpoint: :dialer
      }

      assert %PeerId{} = event.peer_id
      assert event.num_established == 1
      assert event.endpoint == :dialer
    end
  end

  describe "ConnectionClosed" do
    test "creates event with peer_id and cause" do
      event = %Event.ConnectionClosed{
        peer_id: PeerId.new!("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"),
        num_established: 0,
        cause: :keep_alive_timeout
      }

      assert event.num_established == 0
      assert event.cause == :keep_alive_timeout
    end
  end

  describe "NewListenAddr" do
    test "creates event with address" do
      event = %Event.NewListenAddr{
        address: "/ip4/127.0.0.1/tcp/4001",
        listener_id: "listener-1"
      }

      assert event.address == "/ip4/127.0.0.1/tcp/4001"
    end
  end

  describe "GossipsubMessage" do
    test "creates event with topic and data" do
      event = %Event.GossipsubMessage{
        topic: "my-topic",
        data: "hello world",
        source: PeerId.new!("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"),
        message_id: "msg-123"
      }

      assert event.topic == "my-topic"
      assert event.data == "hello world"
      assert %PeerId{} = event.source
    end

    test "source can be nil for anonymous messages" do
      event = %Event.GossipsubMessage{
        topic: "my-topic",
        data: <<1, 2, 3>>,
        source: nil,
        message_id: "msg-456"
      }

      assert event.source == nil
    end
  end

  describe "PeerDiscovered" do
    test "creates event with peer_id and addresses" do
      event = %Event.PeerDiscovered{
        peer_id: PeerId.new!("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"),
        addresses: ["/ip4/192.168.1.1/tcp/4001"]
      }

      assert length(event.addresses) == 1
    end
  end

  describe "DHTQueryResult" do
    test "creates get_record result" do
      event = %Event.DHTQueryResult{
        query_id: "q-1",
        result: {:found_record, "key-1", "value-1"}
      }

      assert event.query_id == "q-1"
      assert {:found_record, _, _} = event.result
    end

    test "creates not_found result" do
      event = %Event.DHTQueryResult{
        query_id: "q-2",
        result: :not_found
      }

      assert event.result == :not_found
    end
  end

  describe "from_raw/1" do
    test "parses connection_established tuple" do
      raw =
        {:connection_established, "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN", 1,
         :dialer}

      assert {:ok, %Event.ConnectionEstablished{}} = Event.from_raw(raw)
    end

    test "parses connection_closed tuple" do
      raw =
        {:connection_closed, "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN", 0,
         :keep_alive_timeout}

      assert {:ok, %Event.ConnectionClosed{}} = Event.from_raw(raw)
    end

    test "parses gossipsub_message tuple" do
      raw =
        {:gossipsub_message, "topic", <<1, 2, 3>>,
         "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN", "msg-1"}

      assert {:ok, %Event.GossipsubMessage{}} = Event.from_raw(raw)
    end

    test "parses new_listen_addr tuple" do
      raw = {:new_listen_addr, "/ip4/127.0.0.1/tcp/4001", "listener-1"}
      assert {:ok, %Event.NewListenAddr{}} = Event.from_raw(raw)
    end

    test "parses peer_discovered tuple" do
      raw =
        {:peer_discovered, "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN",
         ["/ip4/192.168.1.1/tcp/4001"]}

      assert {:ok, %Event.PeerDiscovered{}} = Event.from_raw(raw)
    end

    test "returns error for unknown tuple" do
      raw = {:unknown_event, "data"}
      assert {:error, :unknown_event} = Event.from_raw(raw)
    end
  end
end
