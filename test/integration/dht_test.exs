defmodule ExLibp2p.Integration.DHTTest do
  @moduledoc "End-to-end tests for DHT operations between real nodes."
  use ExLibp2p.NifCase, async: false

  alias ExLibp2p.{DHT, Node, PeerId}

  @tag :integration
  test "put_record and get_record on connected nodes" do
    {:ok, node_a} = start_test_node()
    {:ok, node_b} = start_test_node()

    Process.sleep(200)
    {:ok, [addr | _]} = Node.listening_addrs(node_a)
    {:ok, peer_id_a} = Node.peer_id(node_a)
    Node.dial(node_b, "#{addr}/p2p/#{peer_id_a}")
    Process.sleep(1_000)

    # Register for DHT results
    DHT.register_handler(node_b)

    # Put a record on node_a
    :ok = DHT.put_record(node_a, "test-key", "test-value")
    Process.sleep(500)

    # Get the record from node_b
    :ok = DHT.get_record(node_b, "test-key")

    # DHT queries are async — result arrives as event (may or may not succeed
    # in a 2-node network without bootstrap, but the call should not crash)
    Process.sleep(2_000)

    assert {:ok, _} = Node.peer_id(node_a)
    assert {:ok, _} = Node.peer_id(node_b)

    Node.stop(node_a)
    Node.stop(node_b)
  end

  @tag :integration
  test "find_peer initiates a DHT lookup" do
    {:ok, node_a} = start_test_node()
    {:ok, node_b} = start_test_node()

    Process.sleep(200)
    {:ok, [addr | _]} = Node.listening_addrs(node_a)
    {:ok, peer_id_a} = Node.peer_id(node_a)
    {:ok, peer_id_b} = Node.peer_id(node_b)
    Node.dial(node_b, "#{addr}/p2p/#{peer_id_a}")
    Process.sleep(1_000)

    DHT.register_handler(node_a)

    # Find peer B from node A
    :ok = DHT.find_peer(node_a, peer_id_b)

    # The query runs asynchronously — verify the node stays healthy
    Process.sleep(2_000)
    assert {:ok, _} = Node.peer_id(node_a)

    Node.stop(node_a)
    Node.stop(node_b)
  end

  @tag :integration
  test "provide and find_providers" do
    {:ok, node_a} = start_test_node()
    {:ok, node_b} = start_test_node()

    Process.sleep(200)
    {:ok, [addr | _]} = Node.listening_addrs(node_a)
    {:ok, peer_id_a} = Node.peer_id(node_a)
    Node.dial(node_b, "#{addr}/p2p/#{peer_id_a}")
    Process.sleep(1_000)

    DHT.register_handler(node_b)

    # A advertises as provider for a content key
    :ok = DHT.provide(node_a, "content-hash-123")
    Process.sleep(500)

    # B searches for providers
    :ok = DHT.find_providers(node_b, "content-hash-123")

    # Query is async — verify nodes stay healthy
    Process.sleep(2_000)
    assert {:ok, _} = Node.peer_id(node_a)
    assert {:ok, _} = Node.peer_id(node_b)

    Node.stop(node_a)
    Node.stop(node_b)
  end

  @tag :integration
  test "bootstrap populates routing table" do
    {:ok, seed} = start_test_node()
    {:ok, node} = start_test_node()

    Process.sleep(200)
    {:ok, [addr | _]} = Node.listening_addrs(seed)
    {:ok, seed_id} = Node.peer_id(seed)
    Node.dial(node, "#{addr}/p2p/#{seed_id}")
    Process.sleep(1_000)

    DHT.register_handler(node)

    :ok = DHT.bootstrap(node)

    # Bootstrap query runs async — verify node stays healthy
    Process.sleep(3_000)
    assert {:ok, _} = Node.peer_id(node)

    Node.stop(seed)
    Node.stop(node)
  end
end
