defmodule ExLibp2p.Integration.GossipsubTest do
  use ExLibp2p.NifCase, async: false

  alias ExLibp2p.Gossipsub
  alias ExLibp2p.Node

  @tag :integration
  test "two nodes exchange gossipsub messages" do
    # Start two nodes subscribed to the same topic
    {:ok, node_a} = start_test_node(gossipsub_topics: ["test-topic"])
    {:ok, node_b} = start_test_node(gossipsub_topics: ["test-topic"])

    # Register message handlers
    Gossipsub.register_handler(node_a)
    Gossipsub.register_handler(node_b)

    # Connect the nodes
    Process.sleep(200)
    {:ok, [addr | _]} = Node.listening_addrs(node_a)
    {:ok, peer_id_a} = Node.peer_id(node_a)
    :ok = Node.dial(node_b, "#{addr}/p2p/#{peer_id_a}")

    # Wait for connection + GossipSub mesh formation
    Process.sleep(3_000)

    # Publish from node_a
    :ok = Gossipsub.publish(node_a, "test-topic", "hello from A")

    # node_b should receive the message
    assert_receive {:libp2p, :gossipsub_message,
                    %ExLibp2p.Node.Event.GossipsubMessage{
                      topic: topic,
                      data: data
                    }},
                   5_000

    assert topic =~ "test-topic"
    assert data == "hello from A"

    Node.stop(node_a)
    Node.stop(node_b)
  end

  @tag :integration
  test "subscribe and unsubscribe from topics at runtime" do
    {:ok, node} = start_test_node()

    assert :ok = Gossipsub.subscribe(node, "dynamic-topic")
    assert :ok = Gossipsub.unsubscribe(node, "dynamic-topic")

    Node.stop(node)
  end

  @tag :integration
  test "three-node gossipsub mesh" do
    # Three nodes all subscribed to the same topic
    {:ok, node_a} = start_test_node(gossipsub_topics: ["mesh-topic"])
    {:ok, node_b} = start_test_node(gossipsub_topics: ["mesh-topic"])
    {:ok, node_c} = start_test_node(gossipsub_topics: ["mesh-topic"])

    Gossipsub.register_handler(node_c)

    # Connect in a chain: A <-> B <-> C
    Process.sleep(200)
    {:ok, [addr_a | _]} = Node.listening_addrs(node_a)
    {:ok, peer_id_a} = Node.peer_id(node_a)
    {:ok, [addr_b | _]} = Node.listening_addrs(node_b)
    {:ok, peer_id_b} = Node.peer_id(node_b)

    :ok = Node.dial(node_b, "#{addr_a}/p2p/#{peer_id_a}")
    Process.sleep(500)
    :ok = Node.dial(node_c, "#{addr_b}/p2p/#{peer_id_b}")

    # Wait for mesh formation
    Process.sleep(3_000)

    # Publish from A — C should receive via B (gossip propagation)
    :ok = Gossipsub.publish(node_a, "mesh-topic", "mesh message")

    assert_receive {:libp2p, :gossipsub_message,
                    %ExLibp2p.Node.Event.GossipsubMessage{data: "mesh message"}},
                   5_000

    Node.stop(node_a)
    Node.stop(node_b)
    Node.stop(node_c)
  end
end
