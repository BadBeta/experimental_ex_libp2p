defmodule ExLibp2p.NodeTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.Node
  alias ExLibp2p.Node.Event
  alias ExLibp2p.PeerId

  setup do
    {:ok, node} =
      Node.start_link(
        native_module: ExLibp2p.Native.Mock,
        listen_addrs: ["/ip4/127.0.0.1/tcp/0"]
      )

    %{node: node}
  end

  describe "start_link/1" do
    test "starts a node process", %{node: node} do
      assert Process.alive?(node)
    end

    test "rejects invalid config" do
      Process.flag(:trap_exit, true)

      assert {:error, {:failed_to_start, :no_listen_addrs}} =
               Node.start_link(
                 native_module: ExLibp2p.Native.Mock,
                 listen_addrs: []
               )
    end
  end

  describe "peer_id/1" do
    test "returns the node's peer ID", %{node: node} do
      assert {:ok, %PeerId{}} = Node.peer_id(node)
    end
  end

  describe "connected_peers/1" do
    test "returns empty list initially", %{node: node} do
      assert {:ok, []} = Node.connected_peers(node)
    end
  end

  describe "listening_addrs/1" do
    test "returns listen addresses", %{node: node} do
      assert {:ok, addrs} = Node.listening_addrs(node)
      assert is_list(addrs)
    end
  end

  describe "dial/2" do
    test "accepts valid multiaddr string", %{node: node} do
      assert :ok =
               Node.dial(
                 node,
                 "/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"
               )
    end

    test "rejects invalid multiaddr", %{node: node} do
      assert {:error, :invalid_multiaddr} = Node.dial(node, "not a multiaddr")
    end
  end

  describe "publish/3" do
    test "publishes data to a topic", %{node: node} do
      assert :ok = Node.publish(node, "test-topic", "hello")
    end
  end

  describe "subscribe/2" do
    test "subscribes to a topic", %{node: node} do
      assert :ok = Node.subscribe(node, "test-topic")
    end
  end

  describe "unsubscribe/2" do
    test "unsubscribes from a topic", %{node: node} do
      assert :ok = Node.unsubscribe(node, "test-topic")
    end
  end

  describe "event handling" do
    test "dispatches events to registered handlers", %{node: node} do
      :ok = Node.register_handler(node, :connection_established)

      raw_event =
        {:connection_established, "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN", 1,
         :dialer}

      send(node, {:libp2p_event, raw_event})

      assert_receive {:libp2p, :connection_established,
                      %Event.ConnectionEstablished{
                        peer_id: %PeerId{}
                      }},
                     1000
    end

    test "does not dispatch to unregistered handlers", %{node: node} do
      raw_event =
        {:connection_established, "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN", 1,
         :dialer}

      send(node, {:libp2p_event, raw_event})

      refute_receive {:libp2p, _, _}, 100
    end

    test "dispatches gossipsub messages", %{node: node} do
      :ok = Node.register_handler(node, :gossipsub_message)

      raw_event =
        {:gossipsub_message, "my-topic", <<1, 2, 3>>,
         "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN", "msg-1"}

      send(node, {:libp2p_event, raw_event})

      assert_receive {:libp2p, :gossipsub_message,
                      %Event.GossipsubMessage{
                        topic: "my-topic",
                        data: <<1, 2, 3>>
                      }},
                     1000
    end

    test "handles multiple handlers for same event", %{node: node} do
      :ok = Node.register_handler(node, :connection_established)

      # Register a second handler (another process)
      _test_pid = self()
      {:ok, agent} = Agent.start_link(fn -> nil end)
      :ok = Node.register_handler(node, :connection_established, agent)

      raw_event =
        {:connection_established, "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN", 1,
         :dialer}

      send(node, {:libp2p_event, raw_event})

      # We should receive it (agent won't process it, but we do)
      assert_receive {:libp2p, :connection_established, _}, 1000

      Agent.stop(agent)
    end

    test "unregister_handler stops delivery", %{node: node} do
      :ok = Node.register_handler(node, :connection_established)
      :ok = Node.unregister_handler(node, :connection_established)

      raw_event =
        {:connection_established, "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN", 1,
         :dialer}

      send(node, {:libp2p_event, raw_event})

      refute_receive {:libp2p, _, _}, 100
    end

    test "dead handler processes are automatically cleaned up", %{node: node} do
      # Spawn a short-lived process, register it, then let it die
      handler =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      :ok = Node.register_handler(node, :connection_established, handler)

      # Kill the handler
      send(handler, :stop)
      Process.sleep(50)
      refute Process.alive?(handler)

      # Give the :DOWN message time to be processed by the Node
      Process.sleep(50)

      # Now send an event — should not crash the node (no dead PID in handlers)
      raw_event =
        {:connection_established, "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN", 1,
         :dialer}

      send(node, {:libp2p_event, raw_event})
      Process.sleep(50)

      # Node should still be alive and healthy
      assert Process.alive?(node)
      assert {:ok, _} = Node.peer_id(node)
    end

    test "re-registering same pid for same event is a no-op", %{node: node} do
      :ok = Node.register_handler(node, :gossipsub_message)
      :ok = Node.register_handler(node, :gossipsub_message)

      # Send one event — should receive exactly once, not twice
      raw_event =
        {:gossipsub_message, "topic", "data",
         "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN", "msg-1"}

      send(node, {:libp2p_event, raw_event})

      assert_receive {:libp2p, :gossipsub_message, _}, 500
      refute_receive {:libp2p, :gossipsub_message, _}, 200
    end
  end

  describe "stop/1" do
    test "stops the node process" do
      {:ok, node} =
        Node.start_link(
          native_module: ExLibp2p.Native.Mock,
          listen_addrs: ["/ip4/127.0.0.1/tcp/0"]
        )

      assert :ok = Node.stop(node)
      refute Process.alive?(node)
    end
  end
end
