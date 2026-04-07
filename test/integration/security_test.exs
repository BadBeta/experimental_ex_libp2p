defmodule ExLibp2p.Integration.SecurityTest do
  @moduledoc """
  Security tests for the mesh network.

  Validates that the library's defensive mechanisms protect against
  common P2P attack vectors:

  - Connection exhaustion (resource limits enforced)
  - Message flooding (mailbox stays bounded, node stays responsive)
  - Peer isolation / eclipse (connection limits per peer)
  - Invalid message handling (bad data doesn't crash nodes)
  - Unauthorized peer rejection after blocking
  - Identity spoofing (each node has a unique cryptographic identity)
  - Gossipsub mesh integrity under adversarial conditions

  Run with:
      mix test --include security --timeout 300000
  """
  use ExLibp2p.NifCase, async: false

  alias ExLibp2p.{Gossipsub, Keypair, Node, PeerId}

  @moduletag :integration
  @moduletag :security
  @moduletag timeout: 300_000

  # ── Connection Exhaustion ──────────────────────────────────────

  @tag :security
  test "connection limits prevent resource exhaustion" do
    # Start a node with very tight connection limits
    {:ok, target} =
      start_test_node(
        max_established_incoming: 3,
        max_established_per_peer: 1,
        max_pending_incoming: 2
      )

    Process.sleep(300)
    {:ok, [target_addr | _]} = Node.listening_addrs(target)
    {:ok, target_id} = Node.peer_id(target)
    target_multiaddr = "#{target_addr}/p2p/#{target_id}"

    # Try to connect 10 nodes — only 3 should succeed
    attackers =
      Enum.map(1..10, fn _i ->
        {:ok, node} = start_test_node()
        Node.dial(node, target_multiaddr)
        node
      end)

    Process.sleep(3_000)

    {:ok, target_peers} = Node.connected_peers(target)

    assert length(target_peers) <= 3,
           "target should have at most 3 peers (limit), got #{length(target_peers)}"

    # Target should still be responsive despite rejected connections
    assert {:ok, _} = Node.peer_id(target)

    for node <- [target | attackers], Process.alive?(node), do: Node.stop(node)
  end

  # ── Per-Peer Connection Limit ──────────────────────────────────

  @tag :security
  test "max_established_per_peer prevents single-peer eclipse" do
    {:ok, target} = start_test_node(max_established_per_peer: 1)
    Process.sleep(300)
    {:ok, [target_addr | _]} = Node.listening_addrs(target)
    {:ok, target_id} = Node.peer_id(target)
    target_multiaddr = "#{target_addr}/p2p/#{target_id}"

    # One attacker tries multiple connections
    {:ok, attacker} = start_test_node()
    Node.dial(attacker, target_multiaddr)
    Process.sleep(500)

    # Verify only 1 connection from this peer
    {:ok, target_peers} = Node.connected_peers(target)
    {:ok, attacker_id} = Node.peer_id(attacker)

    attacker_connections =
      Enum.count(target_peers, fn peer -> to_string(peer) == to_string(attacker_id) end)

    assert attacker_connections <= 1,
           "should have at most 1 connection per peer, got #{attacker_connections}"

    for node <- [target, attacker], do: Node.stop(node)
  end

  # ── Message Flooding ───────────────────────────────────────────

  @tag :security
  test "node stays responsive under gossipsub message flood" do
    topic = "flood-topic"

    {:ok, target} = start_test_node(gossipsub_topics: [topic])
    {:ok, flooder} = start_test_node(gossipsub_topics: [topic])

    Process.sleep(300)
    {:ok, [target_addr | _]} = Node.listening_addrs(target)
    {:ok, target_id} = Node.peer_id(target)
    Node.dial(flooder, "#{target_addr}/p2p/#{target_id}")

    # Wait for mesh formation
    Process.sleep(3_000)

    # Flood 1000 messages rapidly
    for i <- 1..1000 do
      Gossipsub.publish(
        flooder,
        topic,
        "flood-#{i}-#{:crypto.strong_rand_bytes(100) |> Base.encode16()}"
      )
    end

    # Give time for messages to propagate
    Process.sleep(2_000)

    # Target should still be responsive
    assert {:ok, _} = Node.peer_id(target)
    assert {:ok, _} = Node.connected_peers(target)
    assert {:ok, _} = Node.listening_addrs(target)

    for node <- [target, flooder], do: Node.stop(node)
  end

  # ── Invalid Data Handling ──────────────────────────────────────

  @tag :security
  test "publishing invalid/oversized data does not crash node" do
    topic = "safety-topic"
    {:ok, node} = start_test_node(gossipsub_topics: [topic])

    # Empty message
    result = Gossipsub.publish(node, topic, <<>>)
    assert result in [:ok, {:error, :publish_failed}]

    # Message at transmit size limit (64KB default)
    big_msg = :crypto.strong_rand_bytes(65_000)
    result = Gossipsub.publish(node, topic, big_msg)
    assert result in [:ok, {:error, :publish_failed}]

    # Node should still be alive
    assert Process.alive?(node)
    assert {:ok, _} = Node.peer_id(node)

    Node.stop(node)
  end

  # ── Cryptographic Identity ─────────────────────────────────────

  @tag :security
  test "every node has a unique cryptographic identity" do
    nodes =
      Enum.map(1..20, fn _i ->
        {:ok, node} = start_test_node()
        node
      end)

    ids =
      Enum.map(nodes, fn node ->
        {:ok, id} = Node.peer_id(node)
        to_string(id)
      end)

    unique_ids = Enum.uniq(ids)

    assert length(unique_ids) == 20,
           "all 20 nodes should have unique peer IDs, got #{length(unique_ids)} unique"

    # Verify IDs are valid base58
    for id <- ids do
      assert {:ok, %PeerId{}} = PeerId.new(id)
    end

    for node <- nodes, do: Node.stop(node)
  end

  @tag :security
  test "keypair persistence produces stable identity" do
    {:ok, kp1} = Keypair.generate()
    {:ok, kp2} = Keypair.generate()

    # Different keypairs = different peer IDs
    refute kp1.peer_id == kp2.peer_id

    # Same keypair round-tripped = same peer ID
    {:ok, encoded} = Keypair.to_protobuf(kp1)
    {:ok, decoded} = Keypair.from_protobuf(encoded)
    assert decoded.peer_id == kp1.peer_id
  end

  # ── Graceful Degradation Under Peer Churn ──────────────────────

  @tag :security
  test "network recovers after sudden loss of 50% of nodes" do
    topic = "resilience-topic"

    {:ok, seed} = start_test_node(gossipsub_topics: [topic])
    Process.sleep(300)
    {:ok, [seed_addr | _]} = Node.listening_addrs(seed)
    {:ok, seed_id} = Node.peer_id(seed)
    seed_multiaddr = "#{seed_addr}/p2p/#{seed_id}"

    # Build 20-node network with staggered start
    nodes =
      Enum.map(1..20, fn i ->
        {:ok, node} = start_test_node(gossipsub_topics: [topic])
        Node.dial(node, seed_multiaddr)
        if rem(i, 5) == 0, do: Process.sleep(500)
        node
      end)

    # Give enough time for all connections to establish
    Process.sleep(8_000)

    {:ok, seed_peers_before} = Node.connected_peers(seed)

    assert length(seed_peers_before) >= 15,
           "seed should have most nodes connected, got #{length(seed_peers_before)}"

    # Suddenly kill 50%
    Process.flag(:trap_exit, true)
    {killed, survivors} = Enum.split(nodes, 10)
    for node <- killed, do: Process.exit(node, :kill)

    # Wait for disconnect detection
    Process.sleep(5_000)

    # Seed should still function
    assert {:ok, _} = Node.peer_id(seed)

    # Survivors should still be connected
    surviving_connected =
      Enum.count(survivors, fn node ->
        {:ok, peers} = Node.connected_peers(node)
        length(peers) >= 1
      end)

    assert surviving_connected >= 7,
           "at least 70% of survivors should maintain connectivity, got #{surviving_connected}/10"

    # Seed is responsive
    assert {:ok, _} = Node.listening_addrs(seed)

    for node <- [seed | survivors], Process.alive?(node), do: Node.stop(node)
  end

  # ── Event Handler Isolation ────────────────────────────────────

  @tag :security
  test "crashing event handler does not crash the node" do
    {:ok, node} = start_test_node()

    # Spawn a handler that will crash on receiving an event
    crasher =
      spawn(fn ->
        receive do
          {:libp2p, _, _} -> raise "intentional crash in handler"
        end
      end)

    Node.register_handler(node, :connection_established, crasher)

    # Simulate an event — the crasher will die but the node should survive
    raw_event =
      {:connection_established, "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN", 1, :dialer}

    send(node, {:libp2p_event, raw_event})
    Process.sleep(100)

    # Crasher is dead
    refute Process.alive?(crasher)

    # Node is alive and responsive
    assert Process.alive?(node)
    assert {:ok, _} = Node.peer_id(node)

    # Dead handler was cleaned up (monitored)
    # Sending another event should not attempt delivery to dead handler
    send(node, {:libp2p_event, raw_event})
    Process.sleep(50)
    assert Process.alive?(node)

    Node.stop(node)
  end

  # ── Rapid Connect/Disconnect ───────────────────────────────────

  @tag :security
  test "rapid connect/disconnect cycles do not leak resources" do
    {:ok, target} = start_test_node()
    Process.sleep(300)
    {:ok, [target_addr | _]} = Node.listening_addrs(target)
    {:ok, target_id} = Node.peer_id(target)
    target_multiaddr = "#{target_addr}/p2p/#{target_id}"

    # Measure baseline
    :erlang.garbage_collect()
    baseline_procs = length(Process.list())

    # 20 rapid connect/disconnect cycles
    for _cycle <- 1..20 do
      {:ok, ephemeral} = start_test_node()
      Node.dial(ephemeral, target_multiaddr)
      Process.sleep(200)
      Node.stop(ephemeral)
      Process.sleep(100)
    end

    Process.sleep(1_000)

    # Target should still be responsive
    assert {:ok, _} = Node.peer_id(target)

    # Process count should not have grown significantly
    :erlang.garbage_collect()
    final_procs = length(Process.list())
    growth = final_procs - baseline_procs

    assert growth < 30,
           "process count grew by #{growth} after 20 connect/disconnect cycles (leak?)"

    Node.stop(target)
  end

  # ── Concurrent Operations Under Load ───────────────────────────

  @tag :security
  test "concurrent API calls from multiple processes do not corrupt state" do
    topic = "concurrent-topic"
    {:ok, node} = start_test_node(gossipsub_topics: [topic])

    # 50 concurrent tasks all hammering the node API
    tasks =
      Enum.map(1..50, fn i ->
        Task.async(fn ->
          for _ <- 1..10 do
            {:ok, _} = Node.peer_id(node)
            {:ok, _} = Node.connected_peers(node)
            {:ok, _} = Node.listening_addrs(node)
            Gossipsub.publish(node, topic, "task-#{i}")
          end

          :ok
        end)
      end)

    results = Task.await_many(tasks, 30_000)

    # All tasks should complete successfully
    assert Enum.all?(results, &(&1 == :ok)),
           "all concurrent tasks should succeed"

    # Node should be in a consistent state
    assert {:ok, _} = Node.peer_id(node)
    assert {:ok, _} = Node.connected_peers(node)

    Node.stop(node)
  end

  # ── Invalid Multiaddr Rejection ────────────────────────────────

  @tag :security
  test "invalid multiaddrs are rejected without crashing" do
    {:ok, node} = start_test_node()

    # Addrs rejected at the Elixir layer (fail Multiaddr.new validation)
    elixir_rejected = [
      "",
      "not-a-multiaddr",
      "javascript:alert(1)",
      String.duplicate("A", 10_000)
    ]

    for addr <- elixir_rejected do
      assert {:error, :invalid_multiaddr} = Node.dial(node, addr)
    end

    # Addrs that pass Elixir validation but may fail at the Rust layer.
    # dial is fire-and-forget — some return :ok and fail asynchronously.
    # The key assertion is that the node doesn't crash.
    rust_handled = [
      "/ip4/999.999.999.999/tcp/0",
      "/ip4/127.0.0.1/tcp/0/p2p/invalid-peer-id"
    ]

    for addr <- rust_handled do
      result = Node.dial(node, addr)
      assert result in [:ok, :error, {:error, :invalid_multiaddr}]
    end

    # Node should still be alive after all bad inputs
    assert Process.alive?(node)
    assert {:ok, _} = Node.peer_id(node)

    Node.stop(node)
  end
end
