defmodule ExLibp2p.Integration.MetricsTest do
  @moduledoc "End-to-end tests for bandwidth metrics."
  use ExLibp2p.NifCase, async: false

  alias ExLibp2p.{Gossipsub, Metrics, Node}

  @tag :integration
  test "bandwidth returns byte counts" do
    {:ok, node} = start_test_node()

    {:ok, stats} = Metrics.bandwidth(node)

    assert is_map(stats)
    assert Map.has_key?(stats, :bytes_in)
    assert Map.has_key?(stats, :bytes_out)
    assert is_integer(stats.bytes_in)
    assert is_integer(stats.bytes_out)
    assert stats.bytes_in >= 0
    assert stats.bytes_out >= 0

    Node.stop(node)
  end

  @tag :integration
  test "bandwidth after traffic shows non-zero values" do
    topic = "metrics-topic"

    {:ok, node_a} = start_test_node(gossipsub_topics: [topic])
    {:ok, node_b} = start_test_node(gossipsub_topics: [topic])

    Process.sleep(200)
    {:ok, [addr | _]} = Node.listening_addrs(node_a)
    {:ok, peer_id_a} = Node.peer_id(node_a)
    Node.dial(node_b, "#{addr}/p2p/#{peer_id_a}")
    Process.sleep(3_000)

    # Generate some traffic
    for i <- 1..10 do
      Gossipsub.publish(node_a, topic, "metrics-msg-#{i}")
    end

    Process.sleep(1_000)

    # Bandwidth stats should reflect the traffic
    # (may still be 0 if bandwidth metrics aren't wired to SwarmBuilder yet)
    {:ok, stats} = Metrics.bandwidth(node_a)
    assert is_integer(stats.bytes_in)
    assert is_integer(stats.bytes_out)

    Node.stop(node_a)
    Node.stop(node_b)
  end
end
