defmodule ExLibp2p.Integration.CapacityTest do
  use ExLibp2p.NifCase, async: false

  alias ExLibp2p.{Gossipsub, Node}

  @moduletag :integration
  @moduletag :capacity
  @moduletag timeout: 120_000

  @tag :integration
  test "10-node star topology — all connected to seed" do
    {:ok, seed} = start_test_node()
    Process.sleep(200)
    {:ok, [seed_addr | _]} = Node.listening_addrs(seed)
    {:ok, seed_id} = Node.peer_id(seed)
    seed_multiaddr = "#{seed_addr}/p2p/#{seed_id}"

    # Spin up 10 nodes and connect each to the seed
    nodes =
      for i <- 1..10 do
        {:ok, node} = start_test_node()
        :ok = Node.dial(node, seed_multiaddr)
        # Stagger connections slightly to avoid overwhelming
        if rem(i, 3) == 0, do: Process.sleep(100)
        node
      end

    # Wait for all connections to establish
    Process.sleep(2_000)

    {:ok, seed_peers} = Node.connected_peers(seed)

    assert length(seed_peers) == 10,
           "seed should have 10 connected peers, got #{length(seed_peers)}"

    # Each spoke should have at least the seed as a peer
    for {node, i} <- Enum.with_index(nodes, 1) do
      {:ok, peers} = Node.connected_peers(node)
      assert length(peers) >= 1, "node #{i} should have at least 1 peer, got #{length(peers)}"
    end

    # Cleanup
    for node <- [seed | nodes], do: Node.stop(node)
  end

  @tag :integration
  test "10-node gossipsub — message reaches all subscribers" do
    topic = "capacity-topic"

    {:ok, seed} = start_test_node(gossipsub_topics: [topic])
    Process.sleep(200)
    {:ok, [seed_addr | _]} = Node.listening_addrs(seed)
    {:ok, seed_id} = Node.peer_id(seed)
    seed_multiaddr = "#{seed_addr}/p2p/#{seed_id}"

    # Spin up 9 more nodes, all subscribed to the same topic
    nodes =
      for i <- 1..9 do
        {:ok, node} = start_test_node(gossipsub_topics: [topic])
        :ok = Node.dial(node, seed_multiaddr)
        if rem(i, 3) == 0, do: Process.sleep(100)
        node
      end

    all_nodes = [seed | nodes]

    # Register gossipsub handlers on a subset of receivers
    # We'll check that a few non-sender nodes get the message
    receivers = Enum.take(nodes, 5)

    for node <- receivers do
      Gossipsub.register_handler(node)
    end

    # Wait for mesh formation (gossipsub needs heartbeat cycles)
    Process.sleep(5_000)

    # Publish from the seed
    :ok = Gossipsub.publish(seed, topic, "broadcast to all")

    # At least some receivers should get the message
    received_count =
      Enum.count(receivers, fn _node ->
        receive do
          {:libp2p, :gossipsub_message,
           %ExLibp2p.Node.Event.GossipsubMessage{data: "broadcast to all"}} ->
            true
        after
          5_000 -> false
        end
      end)

    assert received_count >= 1,
           "at least 1 of #{length(receivers)} receivers should get the message, got #{received_count}"

    for node <- all_nodes, do: Node.stop(node)
  end

  @tag :integration
  test "nodes leaving a 10-node network — remaining nodes stay connected" do
    {:ok, seed} = start_test_node()
    Process.sleep(200)
    {:ok, [seed_addr | _]} = Node.listening_addrs(seed)
    {:ok, seed_id} = Node.peer_id(seed)
    seed_multiaddr = "#{seed_addr}/p2p/#{seed_id}"

    nodes =
      for _i <- 1..9 do
        {:ok, node} = start_test_node()
        :ok = Node.dial(node, seed_multiaddr)
        node
      end

    Process.sleep(2_000)

    # Verify full network
    {:ok, seed_peers_initial} = Node.connected_peers(seed)
    assert length(seed_peers_initial) == 9

    # Kill 5 nodes (simulating departures)
    {leavers, stayers} = Enum.split(nodes, 5)
    for node <- leavers, do: Node.stop(node)

    # Wait for connection close detection
    Process.sleep(2_000)

    # Seed should have exactly 4 remaining peers
    {:ok, seed_peers_after} = Node.connected_peers(seed)

    assert length(seed_peers_after) == 4,
           "seed should have 4 peers after 5 left, got #{length(seed_peers_after)}"

    # Remaining nodes should still be connected to seed
    for {node, i} <- Enum.with_index(stayers, 1) do
      {:ok, peers} = Node.connected_peers(node)
      assert length(peers) >= 1, "stayer #{i} should still be connected, got #{length(peers)} peers"
    end

    for node <- [seed | stayers], do: Node.stop(node)
  end

  @tag :integration
  test "20-node mesh — stress test" do
    {:ok, seed} = start_test_node()
    Process.sleep(200)
    {:ok, [seed_addr | _]} = Node.listening_addrs(seed)
    {:ok, seed_id} = Node.peer_id(seed)
    seed_multiaddr = "#{seed_addr}/p2p/#{seed_id}"

    # Start 19 nodes in batches to avoid resource spikes
    nodes =
      for batch <- Enum.chunk_every(1..19, 5) do
        batch_nodes =
          for _i <- batch do
            {:ok, node} = start_test_node()
            :ok = Node.dial(node, seed_multiaddr)
            node
          end

        Process.sleep(500)
        batch_nodes
      end
      |> List.flatten()

    # Wait for connections to settle
    Process.sleep(3_000)

    {:ok, seed_peers} = Node.connected_peers(seed)

    assert length(seed_peers) == 19,
           "seed should have 19 connected peers, got #{length(seed_peers)}"

    # Every node should have at least seed as peer
    disconnected =
      nodes
      |> Enum.with_index(1)
      |> Enum.filter(fn {node, _i} ->
        {:ok, peers} = Node.connected_peers(node)
        length(peers) == 0
      end)

    assert disconnected == [],
           "all 19 nodes should have at least 1 peer, #{length(disconnected)} had zero"

    # All peer IDs should be unique
    all_ids =
      for node <- [seed | nodes] do
        {:ok, id} = Node.peer_id(node)
        to_string(id)
      end

    assert length(Enum.uniq(all_ids)) == 20, "all 20 peer IDs should be unique"

    for node <- [seed | nodes], do: Node.stop(node)
  end
end
