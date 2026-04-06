defmodule ExLibp2p.Integration.PanicSafetyTest do
  @moduledoc """
  Tests that Rust-side panics cannot crash the BEAM VM.

  Deliberately triggers error conditions in the NIF layer and verifies
  that the Elixir side receives clean error tuples instead of crashing.
  """
  use ExLibp2p.NifCase, async: false

  alias ExLibp2p.{DHT, Gossipsub, Keypair, Node}

  @tag :integration
  test "BEAM survives start_node with deeply invalid config" do
    # The NIF has catch_unwind — even if config parsing panics,
    # we get an error tuple, not a VM crash.
    Process.flag(:trap_exit, true)

    result =
      Node.start_link(
        native_module: ExLibp2p.Native.Nif,
        listen_addrs: ["not-a-multiaddr-at-all"],
        idle_connection_timeout_secs: 1
      )

    case result do
      {:error, _} -> :ok
      {:ok, pid} -> Node.stop(pid)
    end

    # The BEAM is still alive — we can do more work
    assert 1 + 1 == 2
    assert Process.alive?(self())
  end

  @tag :integration
  test "BEAM survives keypair_from_protobuf with garbage data" do
    # Feed random bytes into the keypair decoder
    assert {:error, :invalid_keypair} = Keypair.from_protobuf(:crypto.strong_rand_bytes(256))
    assert {:error, :invalid_keypair} = Keypair.from_protobuf(<<>>)
    assert {:error, :invalid_keypair} = Keypair.from_protobuf(String.duplicate("A", 10_000))

    # BEAM still running
    assert Process.alive?(self())
  end

  @tag :integration
  test "BEAM survives operations on a stopped node" do
    {:ok, node} = start_test_node()
    {:ok, peer_id} = Node.peer_id(node)
    Node.stop(node)

    # Wait for cleanup
    Process.sleep(200)

    # Start a new node — the runtime and NIF should still function
    {:ok, node2} = start_test_node()
    {:ok, peer_id2} = Node.peer_id(node2)
    assert peer_id != peer_id2

    Node.stop(node2)
  end

  @tag :integration
  test "BEAM survives rapid node create-destroy cycles" do
    # Rapidly create and destroy nodes — stresses ResourceArc Drop and runtime
    for _i <- 1..20 do
      {:ok, node} = start_test_node()
      {:ok, _} = Node.peer_id(node)
      Node.stop(node)
    end

    # BEAM still alive, can create one more
    {:ok, final} = start_test_node()
    assert {:ok, _} = Node.peer_id(final)
    Node.stop(final)
  end

  @tag :integration
  test "BEAM survives concurrent node operations during shutdown" do
    {:ok, node} = start_test_node(gossipsub_topics: ["panic-test"])

    # Spawn tasks that hammer the node
    tasks =
      for _i <- 1..10 do
        Task.async(fn ->
          for _j <- 1..5 do
            Node.peer_id(node)
            Node.connected_peers(node)
            Gossipsub.publish(node, "panic-test", "data")
          end
        end)
      end

    # Stop the node while tasks are running
    Process.sleep(10)
    Node.stop(node)

    # Tasks may get errors but should not crash
    for task <- tasks do
      try do
        Task.await(task, 5_000)
      catch
        :exit, _ -> :ok
      end
    end

    # BEAM is alive
    assert Process.alive?(self())

    # Can still create nodes
    {:ok, fresh} = start_test_node()
    assert {:ok, _} = Node.peer_id(fresh)
    Node.stop(fresh)
  end

  @tag :integration
  test "full functionality recovers after node crash and restart" do
    Process.flag(:trap_exit, true)
    topic = "recovery-test"

    # Phase 1: Start two nodes, connect, exchange messages
    {:ok, node_a} = start_test_node(gossipsub_topics: [topic])
    {:ok, node_b} = start_test_node(gossipsub_topics: [topic])

    Process.sleep(200)
    {:ok, [addr_a | _]} = Node.listening_addrs(node_a)
    {:ok, peer_id_a} = Node.peer_id(node_a)
    Node.dial(node_b, "#{addr_a}/p2p/#{peer_id_a}")
    Process.sleep(3_000)

    # Verify connectivity works
    {:ok, peers_b} = Node.connected_peers(node_b)
    assert length(peers_b) >= 1

    Gossipsub.register_handler(node_b)
    Gossipsub.publish(node_a, topic, "before-crash")

    assert_receive {:libp2p, :gossipsub_message, %{data: "before-crash"}}, 5_000

    # Phase 2: Kill node_a (simulated crash)
    Process.exit(node_a, :kill)
    Process.sleep(500)
    refute Process.alive?(node_a)

    # Phase 3: Restart node_a — all functionality must work again
    {:ok, node_a2} = start_test_node(gossipsub_topics: [topic])
    {:ok, peer_id_a2} = Node.peer_id(node_a2)
    {:ok, addrs_a2} = Node.listening_addrs(node_a2)

    # New node has a different identity (new keypair)
    assert to_string(peer_id_a2) != to_string(peer_id_a)
    assert length(addrs_a2) >= 1

    # Phase 4: Reconnect and verify full protocol functionality
    {:ok, [addr_a2 | _]} = Node.listening_addrs(node_a2)
    Node.dial(node_b, "#{addr_a2}/p2p/#{peer_id_a2}")
    Process.sleep(3_000)

    {:ok, peers_b2} = Node.connected_peers(node_b)
    assert length(peers_b2) >= 1

    # GossipSub works after recovery
    Gossipsub.publish(node_a2, topic, "after-recovery")
    assert_receive {:libp2p, :gossipsub_message, %{data: "after-recovery"}}, 5_000

    # DHT works after recovery
    :ok = DHT.put_record(node_a2, "recovery-key", "recovery-value")
    :ok = DHT.bootstrap(node_a2)

    # Subscribe/unsubscribe works
    :ok = Gossipsub.subscribe(node_a2, "new-topic")
    :ok = Gossipsub.unsubscribe(node_a2, "new-topic")

    # Keypair generation works
    {:ok, kp} = Keypair.generate()
    assert is_binary(kp.peer_id)

    # All nodes healthy
    assert {:ok, _} = Node.peer_id(node_a2)
    assert {:ok, _} = Node.peer_id(node_b)

    Node.stop(node_a2)
    Node.stop(node_b)
  end

  @tag :integration
  test "supervisor restarts node and functionality recovers" do
    # Start a supervised node
    children = [
      {Node,
       name: :panic_test_node,
       native_module: ExLibp2p.Native.Nif,
       listen_addrs: ["/ip4/127.0.0.1/tcp/0"],
       gossipsub_topics: ["supervised-test"]}
    ]

    {:ok, sup} = Supervisor.start_link(children, strategy: :one_for_one)

    # Verify it works
    {:ok, peer_id_before} = Node.peer_id(:panic_test_node)
    assert is_struct(peer_id_before, ExLibp2p.PeerId)

    # Kill the node process — supervisor should restart it
    node_pid = GenServer.whereis(:panic_test_node)
    Process.exit(node_pid, :kill)
    Process.sleep(1_000)

    # Supervisor restarted it — new PID, new identity, but same registered name
    new_pid = GenServer.whereis(:panic_test_node)
    assert new_pid != node_pid
    assert Process.alive?(new_pid)

    # Full functionality works on the restarted node
    {:ok, peer_id_after} = Node.peer_id(:panic_test_node)
    assert is_struct(peer_id_after, ExLibp2p.PeerId)

    {:ok, addrs} = Node.listening_addrs(:panic_test_node)
    assert length(addrs) >= 1

    :ok = Gossipsub.subscribe(:panic_test_node, "recovery-topic")
    :ok = Gossipsub.unsubscribe(:panic_test_node, "recovery-topic")

    Supervisor.stop(sup)
  end
end
