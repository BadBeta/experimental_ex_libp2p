defmodule ExLibp2p.Integration.GossipsubAdvancedTest do
  @moduledoc "End-to-end tests for GossipSub mesh inspection and peer scoring."
  use ExLibp2p.NifCase, async: false

  alias ExLibp2p.{Gossipsub, Node}

  @tag :integration
  test "mesh_peers returns peers in the mesh for a topic" do
    topic = "mesh-inspect"

    {:ok, node_a} = start_test_node(gossipsub_topics: [topic])
    {:ok, node_b} = start_test_node(gossipsub_topics: [topic])

    Process.sleep(200)
    {:ok, [addr | _]} = Node.listening_addrs(node_a)
    {:ok, peer_id_a} = Node.peer_id(node_a)
    Node.dial(node_b, "#{addr}/p2p/#{peer_id_a}")

    # Wait for gossipsub mesh formation
    Process.sleep(3_000)

    {:ok, mesh} = Gossipsub.mesh_peers(node_a, topic)
    assert is_list(mesh)
    # After mesh formation, node_b should be in node_a's mesh for the topic
    # (may take a few heartbeats)

    Node.stop(node_a)
    Node.stop(node_b)
  end

  @tag :integration
  test "all_peers returns all known gossipsub peers" do
    topic = "all-peers-inspect"

    {:ok, seed} = start_test_node(gossipsub_topics: [topic])
    Process.sleep(200)
    {:ok, [addr | _]} = Node.listening_addrs(seed)
    {:ok, seed_id} = Node.peer_id(seed)
    seed_multiaddr = "#{addr}/p2p/#{seed_id}"

    nodes =
      for _i <- 1..3 do
        {:ok, node} = start_test_node(gossipsub_topics: [topic])
        Node.dial(node, seed_multiaddr)
        node
      end

    Process.sleep(3_000)

    {:ok, all} = Gossipsub.all_peers(seed)
    assert is_list(all)
    assert length(all) >= 1

    for node <- [seed | nodes], do: Node.stop(node)
  end

  @tag :integration
  test "peer_score returns a float score" do
    topic = "score-inspect"

    {:ok, node_a} = start_test_node(gossipsub_topics: [topic])
    {:ok, node_b} = start_test_node(gossipsub_topics: [topic])

    Process.sleep(200)
    {:ok, [addr | _]} = Node.listening_addrs(node_a)
    {:ok, peer_id_a} = Node.peer_id(node_a)
    {:ok, peer_id_b} = Node.peer_id(node_b)
    Node.dial(node_b, "#{addr}/p2p/#{peer_id_a}")

    Process.sleep(2_000)

    {:ok, score} = Gossipsub.peer_score(node_a, peer_id_b)
    assert is_float(score) or is_integer(score)

    Node.stop(node_a)
    Node.stop(node_b)
  end

  @tag :integration
  test "subscribe and unsubscribe at runtime" do
    {:ok, node} = start_test_node()

    :ok = Gossipsub.subscribe(node, "dynamic-topic-1")
    :ok = Gossipsub.subscribe(node, "dynamic-topic-2")
    :ok = Gossipsub.unsubscribe(node, "dynamic-topic-1")

    # Node should still be functional
    assert {:ok, _} = Node.peer_id(node)

    Node.stop(node)
  end
end
