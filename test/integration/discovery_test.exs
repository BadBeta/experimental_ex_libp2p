defmodule ExLibp2p.Integration.DiscoveryTest do
  @moduledoc "End-to-end tests for discovery bootstrap with real nodes."
  use ExLibp2p.NifCase, async: false

  alias ExLibp2p.{Discovery, Node}

  @tag :integration
  test "bootstrap dials peers and triggers DHT bootstrap" do
    {:ok, seed} = start_test_node()
    Process.sleep(200)
    {:ok, [addr | _]} = Node.listening_addrs(seed)
    {:ok, seed_id} = Node.peer_id(seed)
    seed_multiaddr = "#{addr}/p2p/#{seed_id}"

    {:ok, node} = start_test_node()
    Discovery.register_handler(node)

    {:ok, results} = Discovery.bootstrap(node, [seed_multiaddr])
    assert results == [:ok]

    # Should connect to seed
    Process.sleep(2_000)
    {:ok, peers} = Node.connected_peers(node)
    assert length(peers) >= 1

    Node.stop(seed)
    Node.stop(node)
  end

  @tag :integration
  test "bootstrap with empty list returns :ok" do
    {:ok, node} = start_test_node()
    assert :ok = Discovery.bootstrap(node, [])
    Node.stop(node)
  end
end
