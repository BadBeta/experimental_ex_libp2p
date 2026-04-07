defmodule ExLibp2p.Integration.MdnsDiscoveryTest do
  @moduledoc """
  Tests that nodes discover each other automatically via mDNS
  on the local network — no manual dialing needed.
  """
  use ExLibp2p.NifCase, async: false

  alias ExLibp2p.{Discovery, Node}

  @moduletag timeout: 60_000

  @tag :integration
  test "two nodes discover each other via mDNS without dialing" do
    {:ok, node_a} = start_test_node(enable_mdns: true)
    {:ok, node_b} = start_test_node(enable_mdns: true)

    Discovery.register_handler(node_a)
    Discovery.register_handler(node_b)

    # mDNS query interval is ~5s. Wait up to 30s for discovery.
    assert_receive {:libp2p, :peer_discovered,
                    %ExLibp2p.Node.Event.PeerDiscovered{addresses: addrs}},
                   30_000

    assert length(addrs) >= 1

    # Poll for connection instead of fixed sleep — mDNS discovery
    # doesn't guarantee immediate connection.
    connected =
      poll_until(10_000, fn ->
        {:ok, peers_a} = Node.connected_peers(node_a)
        {:ok, peers_b} = Node.connected_peers(node_b)
        length(peers_a) >= 1 or length(peers_b) >= 1
      end)

    assert connected,
           "at least one node should have auto-connected via mDNS within 10s"

    Node.stop(node_a)
    Node.stop(node_b)
  end

  @tag :integration
  test "third node discovers existing mDNS peers automatically" do
    {:ok, node_a} = start_test_node(enable_mdns: true)
    {:ok, node_b} = start_test_node(enable_mdns: true)

    # Let A and B discover each other first
    Process.sleep(8_000)

    {:ok, node_c} = start_test_node(enable_mdns: true)
    Discovery.register_handler(node_c)

    discovered_peers = collect_discoveries(20_000)

    assert length(discovered_peers) >= 1,
           "node_c should discover at least 1 peer via mDNS, found #{length(discovered_peers)}"

    Node.stop(node_a)
    Node.stop(node_b)
    Node.stop(node_c)
  end

  @tag :integration
  test "node leaving is noticed by mDNS peers" do
    {:ok, node_a} = start_test_node(enable_mdns: true)
    {:ok, node_b} = start_test_node(enable_mdns: true)

    Node.register_handler(node_b, :connection_established)
    Node.register_handler(node_b, :connection_closed)

    # Wait for mDNS discovery + connection (up to 30s)
    assert_receive {:libp2p, :connection_established, _}, 30_000

    {:ok, peers_before} = Node.connected_peers(node_b)
    assert length(peers_before) >= 1

    Node.stop(node_a)

    assert_receive {:libp2p, :connection_closed, _}, 15_000

    poll_until(3_000, fn ->
      {:ok, peers} = Node.connected_peers(node_b)
      length(peers) == 0
    end)

    Node.stop(node_b)
  end

  # Polls a function every 200ms until it returns true or timeout
  defp poll_until(timeout_ms, fun) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_poll(deadline, fun)
  end

  defp do_poll(deadline, fun) do
    if fun.() do
      true
    else
      remaining = deadline - System.monotonic_time(:millisecond)

      if remaining <= 0 do
        false
      else
        Process.sleep(200)
        do_poll(deadline, fun)
      end
    end
  end

  defp collect_discoveries(timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_collect(deadline, [])
  end

  defp do_collect(deadline, acc) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      acc
    else
      receive do
        {:libp2p, :peer_discovered, %ExLibp2p.Node.Event.PeerDiscovered{peer_id: pid}} ->
          do_collect(deadline, [pid | acc])
      after
        min(remaining, 1000) -> acc
      end
    end
  end
end
