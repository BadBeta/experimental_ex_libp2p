defmodule ExLibp2p.Integration.NodeLifecycleTest do
  use ExLibp2p.NifCase, async: false

  alias ExLibp2p.Node

  @tag :integration
  test "starts and stops a node" do
    {:ok, node} = start_test_node()

    assert {:ok, peer_id} = Node.peer_id(node)
    assert is_struct(peer_id, ExLibp2p.PeerId)

    assert {:ok, addrs} = Node.listening_addrs(node)
    assert is_list(addrs)

    assert {:ok, []} = Node.connected_peers(node)

    :ok = Node.stop(node)
    refute Process.alive?(node)
  end

  @tag :integration
  test "node has a unique peer ID" do
    {:ok, node_a} = start_test_node()
    {:ok, node_b} = start_test_node()

    {:ok, id_a} = Node.peer_id(node_a)
    {:ok, id_b} = Node.peer_id(node_b)

    refute id_a == id_b

    Node.stop(node_a)
    Node.stop(node_b)
  end

  @tag :integration
  test "node reports listen addresses" do
    {:ok, node} = start_test_node(listen_addrs: ["/ip4/127.0.0.1/tcp/0"])

    # Give the node time to bind
    Process.sleep(100)

    {:ok, addrs} = Node.listening_addrs(node)
    assert length(addrs) >= 1

    # Should have resolved the :0 port to an actual port
    for addr <- addrs do
      assert String.contains?(addr, "/ip4/127.0.0.1/tcp/")
    end

    Node.stop(node)
  end
end
