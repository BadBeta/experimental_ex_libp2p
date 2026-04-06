defmodule ExLibp2p.Integration.ConnectivityTest do
  use ExLibp2p.NifCase, async: false

  alias ExLibp2p.Node

  @tag :integration
  test "two nodes can connect" do
    {:ok, node_a} = start_test_node()
    {:ok, node_b} = start_test_node()

    Node.register_handler(node_a, :connection_established)
    Node.register_handler(node_b, :connection_established)

    Process.sleep(200)
    {:ok, [addr | _]} = Node.listening_addrs(node_a)
    {:ok, peer_id_a} = Node.peer_id(node_a)

    :ok = Node.dial(node_b, "#{addr}/p2p/#{peer_id_a}")

    assert_receive {:libp2p, :connection_established, event}, 5_000
    assert is_struct(event, ExLibp2p.Node.Event.ConnectionEstablished)

    Process.sleep(200)
    {:ok, peers_a} = Node.connected_peers(node_a)
    {:ok, peers_b} = Node.connected_peers(node_b)

    assert length(peers_a) >= 1
    assert length(peers_b) >= 1

    Node.stop(node_a)
    Node.stop(node_b)
  end

  @tag :integration
  test "connection events include peer IDs" do
    {:ok, node_a} = start_test_node()
    {:ok, node_b} = start_test_node()

    Node.register_handler(node_b, :connection_established)

    Process.sleep(200)
    {:ok, [addr | _]} = Node.listening_addrs(node_a)
    {:ok, peer_id_a} = Node.peer_id(node_a)

    :ok = Node.dial(node_b, "#{addr}/p2p/#{peer_id_a}")

    assert_receive {:libp2p, :connection_established,
                    %ExLibp2p.Node.Event.ConnectionEstablished{peer_id: connected_peer}},
                   5_000

    assert to_string(connected_peer) == to_string(peer_id_a)

    Node.stop(node_a)
    Node.stop(node_b)
  end

  @tag :integration
  test "new node joins an existing network" do
    # Start a seed node
    {:ok, seed} = start_test_node()
    Process.sleep(200)
    {:ok, [seed_addr | _]} = Node.listening_addrs(seed)
    {:ok, seed_id} = Node.peer_id(seed)
    seed_multiaddr = "#{seed_addr}/p2p/#{seed_id}"

    # Two nodes already connected to the seed
    {:ok, node_a} = start_test_node()
    {:ok, node_b} = start_test_node()
    :ok = Node.dial(node_a, seed_multiaddr)
    :ok = Node.dial(node_b, seed_multiaddr)
    Process.sleep(500)

    # Verify seed sees both peers
    {:ok, seed_peers} = Node.connected_peers(seed)
    assert length(seed_peers) == 2

    # A new node arrives and joins
    {:ok, newcomer} = start_test_node()
    Node.register_handler(newcomer, :connection_established)

    :ok = Node.dial(newcomer, seed_multiaddr)

    assert_receive {:libp2p, :connection_established,
                    %ExLibp2p.Node.Event.ConnectionEstablished{peer_id: joined_peer}},
                   5_000

    assert to_string(joined_peer) == to_string(seed_id)

    # Seed now has 3 peers
    Process.sleep(200)
    {:ok, seed_peers_after} = Node.connected_peers(seed)
    assert length(seed_peers_after) == 3

    # Newcomer sees at least the seed
    {:ok, newcomer_peers} = Node.connected_peers(newcomer)
    assert length(newcomer_peers) >= 1

    for n <- [seed, node_a, node_b, newcomer], do: Node.stop(n)
  end

  @tag :integration
  test "node departing triggers connection_closed on remaining peers" do
    {:ok, node_a} = start_test_node()
    {:ok, node_b} = start_test_node()

    # Connect them
    Process.sleep(200)
    {:ok, [addr | _]} = Node.listening_addrs(node_a)
    {:ok, peer_id_a} = Node.peer_id(node_a)
    :ok = Node.dial(node_b, "#{addr}/p2p/#{peer_id_a}")
    Process.sleep(500)

    # Verify connected
    {:ok, peers_b} = Node.connected_peers(node_b)
    assert length(peers_b) == 1

    # Register for close events on node_b
    Node.register_handler(node_b, :connection_closed)

    # node_a departs (graceful stop)
    Node.stop(node_a)

    # node_b should see the connection close
    assert_receive {:libp2p, :connection_closed,
                    %ExLibp2p.Node.Event.ConnectionClosed{
                      peer_id: departed_peer,
                      num_established: 0
                    }},
                   5_000

    assert to_string(departed_peer) == to_string(peer_id_a)

    # node_b has no peers now
    Process.sleep(200)
    {:ok, peers_after} = Node.connected_peers(node_b)
    assert peers_after == []

    Node.stop(node_b)
  end

  @tag :integration
  test "multiple nodes join and leave dynamically" do
    # Start a seed
    {:ok, seed} = start_test_node()
    Process.sleep(200)
    {:ok, [seed_addr | _]} = Node.listening_addrs(seed)
    {:ok, seed_id} = Node.peer_id(seed)
    seed_multiaddr = "#{seed_addr}/p2p/#{seed_id}"

    Node.register_handler(seed, :connection_established)
    Node.register_handler(seed, :connection_closed)

    # Phase 1: 3 nodes join one by one
    joiners =
      for _i <- 1..3 do
        {:ok, node} = start_test_node()
        :ok = Node.dial(node, seed_multiaddr)
        assert_receive {:libp2p, :connection_established, _}, 5_000
        node
      end

    Process.sleep(300)
    {:ok, seed_peers} = Node.connected_peers(seed)
    assert length(seed_peers) == 3

    # Phase 2: First two leave
    [leaver1, leaver2, stayer] = joiners
    Node.stop(leaver1)
    assert_receive {:libp2p, :connection_closed, _}, 5_000

    Node.stop(leaver2)
    assert_receive {:libp2p, :connection_closed, _}, 5_000

    Process.sleep(300)
    {:ok, seed_peers_after} = Node.connected_peers(seed)
    assert length(seed_peers_after) == 1

    # Phase 3: Two new nodes join
    for _i <- 1..2 do
      {:ok, node} = start_test_node()
      :ok = Node.dial(node, seed_multiaddr)
      assert_receive {:libp2p, :connection_established, _}, 5_000
      node
    end

    Process.sleep(300)
    {:ok, final_peers} = Node.connected_peers(seed)
    # stayer + 2 new = 3
    assert length(final_peers) == 3

    Node.stop(stayer)
    Node.stop(seed)
  end
end
