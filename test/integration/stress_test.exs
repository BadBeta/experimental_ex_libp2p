defmodule ExLibp2p.Integration.StressTest do
  @moduledoc """
  100-node stress test with 10 nodes churning in and out via mDNS discovery.

  The network is bootstrapped via a seed node (explicit dial), then mDNS
  handles discovery of the 10 churning nodes that arrive and depart in waves.

  Run with:
      mix test --include stress --timeout 600000
  """
  use ExLibp2p.NifCase, async: false

  alias ExLibp2p.{Discovery, Gossipsub, Node}
  alias ExLibp2p.Node.Event.GossipsubMessage
  alias ExLibp2p.TestMessages
  alias ExLibp2p.TestMessages.{BlockAnnouncement, ChatMessage, SensorReading}

  @moduletag :integration
  @moduletag :stress
  @moduletag timeout: 600_000

  # How many stable nodes form the backbone (connected via explicit dial)
  @backbone_count 90
  # How many nodes churn in and out via mDNS
  @churn_count 10
  # Batch size for starting backbone nodes
  @batch_size 10
  # How long to wait for mDNS discovery (seconds)
  @mdns_discovery_wait 15_000
  # Pause between churn waves
  @churn_wave_pause 5_000

  @tag :stress
  test "100-node network with 10 churning mDNS-discovered nodes" do
    # ── Phase 1: Bootstrap the backbone ──────────────────────────
    IO.puts("\n[stress] Phase 1: Starting seed node...")
    {:ok, seed} = start_test_node(enable_mdns: true)
    Process.sleep(500)
    {:ok, [seed_addr | _]} = Node.listening_addrs(seed)
    {:ok, seed_id} = Node.peer_id(seed)
    seed_multiaddr = "#{seed_addr}/p2p/#{seed_id}"

    IO.puts("[stress] Seed: #{seed_id}")

    IO.puts(
      "[stress] Phase 1: Starting #{@backbone_count} backbone nodes in batches of #{@batch_size}..."
    )

    backbone_nodes =
      1..@backbone_count
      |> Enum.chunk_every(@batch_size)
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {batch, batch_num} ->
        nodes =
          Enum.map(batch, fn _i ->
            {:ok, node} = start_test_node(enable_mdns: true)
            :ok = Node.dial(node, seed_multiaddr)
            node
          end)

        IO.puts(
          "[stress]   batch #{batch_num}/#{ceil(@backbone_count / @batch_size)} — #{length(nodes)} nodes started"
        )

        Process.sleep(1_000)
        nodes
      end)

    # Let connections settle
    IO.puts("[stress] Phase 1: Waiting for backbone to stabilize...")
    Process.sleep(5_000)

    {:ok, seed_peers} = Node.connected_peers(seed)
    backbone_peer_count = length(seed_peers)

    IO.puts("[stress] Phase 1: Seed has #{backbone_peer_count} connected peers")

    assert backbone_peer_count >= @backbone_count * 0.9,
           "seed should have at least 90% of #{@backbone_count} backbone peers connected, got #{backbone_peer_count}"

    # Spot-check a few backbone nodes have connectivity
    sample = Enum.take_random(backbone_nodes, 5)

    for node <- sample do
      {:ok, peers} = Node.connected_peers(node)

      assert length(peers) >= 1,
             "sampled backbone node should have at least 1 peer, got #{length(peers)}"
    end

    # ── Phase 2: Churn wave 1 — 10 nodes arrive via mDNS ────────
    IO.puts(
      "[stress] Phase 2: #{@churn_count} nodes arriving (mDNS discovery, no explicit dial)..."
    )

    # Pick one backbone node to observe discoveries
    observer = hd(backbone_nodes)
    Discovery.register_handler(observer)
    Node.register_handler(observer, :connection_established)

    churn_wave_1 =
      Enum.map(1..@churn_count, fn i ->
        {:ok, node} = start_test_node(enable_mdns: true)

        if rem(i, 3) == 0 do
          Process.sleep(200)
        end

        node
      end)

    IO.puts("[stress] Phase 2: Waiting #{div(@mdns_discovery_wait, 1000)}s for mDNS discovery...")
    Process.sleep(@mdns_discovery_wait)

    # Check how many of the churn nodes got discovered and connected
    {:ok, seed_peers_after_wave1} = Node.connected_peers(seed)
    new_connections = length(seed_peers_after_wave1) - backbone_peer_count

    IO.puts(
      "[stress] Phase 2: Seed now has #{length(seed_peers_after_wave1)} peers (+#{new_connections} from churn)"
    )

    # At least some churn nodes should have been discovered via mDNS
    churn_connected =
      Enum.count(churn_wave_1, fn node ->
        {:ok, peers} = Node.connected_peers(node)
        length(peers) >= 1
      end)

    IO.puts("[stress] Phase 2: #{churn_connected}/#{@churn_count} churn nodes have peers")

    assert churn_connected >= 1,
           "at least 1 of #{@churn_count} churn nodes should have connected via mDNS, got #{churn_connected}"

    # ── Phase 3: Churn wave 1 departs ────────────────────────────
    IO.puts("[stress] Phase 3: #{@churn_count} churn nodes departing...")
    Node.register_handler(observer, :connection_closed)

    for node <- churn_wave_1 do
      Node.stop(node)
    end

    IO.puts("[stress] Phase 3: Waiting for departures to propagate...")
    Process.sleep(@churn_wave_pause)

    {:ok, seed_peers_after_departure} = Node.connected_peers(seed)

    IO.puts(
      "[stress] Phase 3: Seed has #{length(seed_peers_after_departure)} peers after churn departure"
    )

    # Should be back to roughly backbone count
    assert length(seed_peers_after_departure) >= @backbone_count * 0.85,
           "seed should retain most backbone peers, got #{length(seed_peers_after_departure)}"

    # Backbone nodes should still be healthy
    healthy_backbone =
      Enum.count(backbone_nodes, fn node ->
        {:ok, peers} = Node.connected_peers(node)
        length(peers) >= 1
      end)

    IO.puts("[stress] Phase 3: #{healthy_backbone}/#{@backbone_count} backbone nodes still healthy")

    assert healthy_backbone >= @backbone_count * 0.9,
           "at least 90% of backbone should remain healthy, got #{healthy_backbone}/#{@backbone_count}"

    # ── Phase 4: Churn wave 2 — 10 new nodes arrive ─────────────
    IO.puts("[stress] Phase 4: #{@churn_count} new nodes arriving (mDNS)...")

    churn_wave_2 =
      Enum.map(1..@churn_count, fn i ->
        {:ok, node} = start_test_node(enable_mdns: true)

        if rem(i, 3) == 0 do
          Process.sleep(200)
        end

        node
      end)

    IO.puts("[stress] Phase 4: Waiting #{div(@mdns_discovery_wait, 1000)}s for mDNS discovery...")
    Process.sleep(@mdns_discovery_wait)

    {:ok, seed_peers_wave2} = Node.connected_peers(seed)

    churn2_connected =
      Enum.count(churn_wave_2, fn node ->
        {:ok, peers} = Node.connected_peers(node)
        length(peers) >= 1
      end)

    IO.puts(
      "[stress] Phase 4: Seed has #{length(seed_peers_wave2)} peers, #{churn2_connected}/#{@churn_count} wave-2 nodes connected"
    )

    assert churn2_connected >= 1,
           "at least 1 wave-2 churn node should have connected via mDNS"

    # ── Phase 5: Final network health check ──────────────────────
    IO.puts("[stress] Phase 5: Final health check...")

    total_alive = [seed | backbone_nodes] ++ churn_wave_2
    total_count = length(total_alive)

    all_ids =
      Enum.map(total_alive, fn node ->
        {:ok, id} = Node.peer_id(node)
        to_string(id)
      end)

    unique_ids = length(Enum.uniq(all_ids))
    IO.puts("[stress] Phase 5: #{unique_ids} unique peer IDs across #{total_count} nodes")
    assert unique_ids == total_count, "all peer IDs should be unique"

    total_connected =
      Enum.count(total_alive, fn node ->
        {:ok, peers} = Node.connected_peers(node)
        length(peers) >= 1
      end)

    connectivity_pct = Float.round(total_connected / total_count * 100, 1)

    IO.puts(
      "[stress] Phase 5: #{total_connected}/#{total_count} nodes connected (#{connectivity_pct}%)"
    )

    assert total_connected >= total_count * 0.85,
           "at least 85% of nodes should have connectivity, got #{total_connected}/#{total_count}"

    # ── Cleanup ──────────────────────────────────────────────────
    IO.puts("[stress] Cleanup: Stopping #{total_count} nodes...")

    total_alive
    |> Enum.chunk_every(20)
    |> Enum.each(fn batch ->
      Enum.each(batch, &Node.stop/1)
      Process.sleep(200)
    end)

    IO.puts("[stress] Done.")
  end

  @tag :stress
  test "100-node gossipsub — message propagation under churn" do
    topic = "stress-gossip"

    IO.puts("\n[stress-gossip] Starting seed...")
    {:ok, seed} = start_test_node(enable_mdns: true, gossipsub_topics: [topic])
    Process.sleep(500)
    {:ok, [seed_addr | _]} = Node.listening_addrs(seed)
    {:ok, seed_id} = Node.peer_id(seed)
    seed_multiaddr = "#{seed_addr}/p2p/#{seed_id}"

    # 50 backbone nodes subscribed to the topic
    backbone_count = 50

    IO.puts("[stress-gossip] Starting #{backbone_count} backbone nodes...")

    backbone =
      1..backbone_count
      |> Enum.chunk_every(@batch_size)
      |> Enum.flat_map(fn batch ->
        nodes =
          Enum.map(batch, fn _i ->
            {:ok, node} = start_test_node(enable_mdns: true, gossipsub_topics: [topic])
            :ok = Node.dial(node, seed_multiaddr)
            node
          end)

        Process.sleep(1_000)
        nodes
      end)

    # Wait for gossipsub mesh formation
    IO.puts("[stress-gossip] Waiting for mesh formation...")
    Process.sleep(8_000)

    # Register handlers on 10 random backbone nodes
    listeners = Enum.take_random(backbone, 10)
    for node <- listeners, do: Gossipsub.register_handler(node)

    # Publish from seed
    IO.puts("[stress-gossip] Publishing message from seed...")
    :ok = Gossipsub.publish(seed, topic, "stress-test-message")

    # Count how many listeners received it
    received =
      Enum.count(listeners, fn _node ->
        receive do
          {:libp2p, :gossipsub_message, %GossipsubMessage{data: "stress-test-message"}} ->
            true
        after
          10_000 -> false
        end
      end)

    IO.puts("[stress-gossip] #{received}/#{length(listeners)} listeners received the message")

    assert received >= 1,
           "at least 1 of #{length(listeners)} listeners should receive the message"

    # Now churn: stop 10 backbone nodes, start 10 new ones
    IO.puts("[stress-gossip] Churning 10 nodes...")
    {leavers, _stayers} = Enum.split(backbone, 10)
    for node <- leavers, do: Node.stop(node)

    newcomers =
      Enum.map(1..10, fn _i ->
        {:ok, node} = start_test_node(enable_mdns: true, gossipsub_topics: [topic])
        :ok = Node.dial(node, seed_multiaddr)
        node
      end)

    # Wait for mesh to reform
    Process.sleep(8_000)

    # Register on newcomers and publish again
    for node <- newcomers, do: Gossipsub.register_handler(node)

    IO.puts("[stress-gossip] Publishing second message after churn...")
    :ok = Gossipsub.publish(seed, topic, "post-churn-message")

    post_churn_received =
      Enum.count(newcomers, fn _node ->
        receive do
          {:libp2p, :gossipsub_message, %GossipsubMessage{data: "post-churn-message"}} ->
            true
        after
          10_000 -> false
        end
      end)

    IO.puts(
      "[stress-gossip] #{post_churn_received}/#{length(newcomers)} newcomers received post-churn message"
    )

    assert post_churn_received >= 1,
           "at least 1 newcomer should receive the post-churn message"

    # Cleanup
    all_alive = [seed | backbone -- leavers] ++ newcomers
    IO.puts("[stress-gossip] Cleanup: stopping #{length(all_alive)} nodes...")
    Enum.each(all_alive, &Node.stop/1)
    IO.puts("[stress-gossip] Done.")
  end

  @tag :stress
  test "100-node structured messaging — point-to-point and broadcast with structs" do
    # ── Setup: 3 topic channels ──────────────────────────────────
    # "chat"    — ChatMessage structs, conversational
    # "sensors" — SensorReading structs, many-to-many telemetry
    # "blocks"  — BlockAnnouncement structs, broadcast from producers
    topics = ["chat", "sensors", "blocks"]

    IO.puts("\n[stress-msg] Starting seed node...")
    {:ok, seed} = start_test_node(enable_mdns: true, gossipsub_topics: topics)
    Process.sleep(500)
    {:ok, [seed_addr | _]} = Node.listening_addrs(seed)
    {:ok, seed_id} = Node.peer_id(seed)
    seed_multiaddr = "#{seed_addr}/p2p/#{seed_id}"

    # ── Phase 1: Start 99 nodes in batches ───────────────────────
    node_count = 99
    IO.puts("[stress-msg] Starting #{node_count} nodes in batches of #{@batch_size}...")

    nodes =
      1..node_count
      |> Enum.chunk_every(@batch_size)
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {batch, batch_num} ->
        batch_nodes =
          Enum.map(batch, fn _i ->
            {:ok, node} = start_test_node(enable_mdns: true, gossipsub_topics: topics)
            :ok = Node.dial(node, seed_multiaddr)
            node
          end)

        IO.puts("[stress-msg]   batch #{batch_num} — #{length(batch_nodes)} nodes started")
        Process.sleep(1_000)
        batch_nodes
      end)

    all_nodes = [seed | nodes]

    # Wait for gossipsub mesh to form across all topics
    IO.puts("[stress-msg] Waiting for mesh formation across 3 topics...")
    Process.sleep(10_000)

    # Build a lookup: node pid → peer_id string
    node_ids =
      Map.new(all_nodes, fn node ->
        {:ok, id} = Node.peer_id(node)
        {node, to_string(id)}
      end)

    # ── Phase 2: Broadcast — block announcements from 5 producers ─
    IO.puts("[stress-msg] Phase 2: Block announcements (broadcast)...")

    producers = Enum.take_random(nodes, 5)
    # 20 random listeners for blocks
    block_listeners = Enum.take_random(nodes -- producers, 20)
    for node <- block_listeners, do: Gossipsub.register_handler(node)

    # Each producer announces 3 blocks
    for {producer, p_idx} <- Enum.with_index(producers, 1) do
      producer_id = node_ids[producer]

      for height <- 1..3 do
        block = BlockAnnouncement.new(producer_id, height * 100 + p_idx, tx_count: height * 10)
        :ok = Gossipsub.publish(producer, "blocks", TestMessages.encode!(block))
      end
    end

    # 15 messages published total — collect what we can
    Process.sleep(3_000)
    block_received = drain_gossipsub_messages("blocks")

    blocks_decoded =
      Enum.flat_map(block_received, fn data ->
        case BlockAnnouncement.decode(data) do
          {:ok, block} -> [block]
          _ -> []
        end
      end)

    IO.puts(
      "[stress-msg] Phase 2: #{length(blocks_decoded)} block announcements received " <>
        "from #{length(Enum.uniq_by(blocks_decoded, & &1.producer))} unique producers"
    )

    assert length(blocks_decoded) >= 1,
           "at least 1 block announcement should be received"

    # Verify struct integrity
    for block <- blocks_decoded do
      assert is_binary(block.block_hash)
      assert byte_size(block.block_hash) == 32
      assert is_integer(block.height) and block.height > 0
      assert is_binary(block.producer) and byte_size(block.producer) > 40
      assert is_integer(block.tx_count) and block.tx_count >= 0
    end

    # ── Phase 3: Sensor telemetry — 20 nodes publish readings ────
    IO.puts("[stress-msg] Phase 3: Sensor readings (many-to-many)...")

    sensor_publishers = Enum.take_random(nodes, 20)
    sensor_listeners = Enum.take_random(nodes -- sensor_publishers, 15)
    for node <- sensor_listeners, do: Gossipsub.register_handler(node)

    for {publisher, idx} <- Enum.with_index(sensor_publishers, 1) do
      publisher_id = node_ids[publisher]

      # Each node sends 5 readings from different sensors
      for seq <- 1..5 do
        sensor = Enum.random(["temperature", "humidity", "pressure", "co2", "light"])
        value = :rand.uniform() * 100

        reading =
          SensorReading.new(publisher_id, sensor, Float.round(value, 2), "raw", sequence: seq)

        :ok = Gossipsub.publish(publisher, "sensors", TestMessages.encode!(reading))
      end

      if rem(idx, 5) == 0, do: Process.sleep(100)
    end

    # 100 readings published total
    Process.sleep(3_000)
    sensor_received = drain_gossipsub_messages("sensors")

    readings_decoded =
      Enum.flat_map(sensor_received, fn data ->
        case SensorReading.decode(data) do
          {:ok, reading} -> [reading]
          _ -> []
        end
      end)

    unique_sensors = Enum.uniq_by(readings_decoded, & &1.sensor) |> length()
    unique_nodes = Enum.uniq_by(readings_decoded, & &1.node_id) |> length()

    IO.puts(
      "[stress-msg] Phase 3: #{length(readings_decoded)} sensor readings received " <>
        "from #{unique_nodes} nodes, #{unique_sensors} sensor types"
    )

    assert length(readings_decoded) >= 1,
           "at least 1 sensor reading should be received"

    for reading <- readings_decoded do
      assert reading.sensor in ["temperature", "humidity", "pressure", "co2", "light"]
      assert is_float(reading.value) or is_integer(reading.value)
      assert reading.unit == "raw"
      assert is_binary(reading.node_id) and byte_size(reading.node_id) > 40
    end

    # ── Phase 4: Chat — conversational point-to-point via topic ──
    IO.puts("[stress-msg] Phase 4: Chat messages (conversational)...")

    # 10 chat pairs — each pair exchanges messages back and forth
    chat_pairs = nodes |> Enum.shuffle() |> Enum.chunk_every(2) |> Enum.take(10)
    chat_listeners = List.flatten(chat_pairs)
    for node <- chat_listeners, do: Gossipsub.register_handler(node)

    for [node_a, node_b] <- chat_pairs do
      id_a = node_ids[node_a]
      id_b = node_ids[node_b]

      # A says hello
      msg1 = ChatMessage.new(id_a, "Hello from #{String.slice(id_a, 0..7)}!")
      :ok = Gossipsub.publish(node_a, "chat", TestMessages.encode!(msg1))

      # B replies
      msg2 = ChatMessage.new(id_b, "Hey back!", reply_to: id_a)
      :ok = Gossipsub.publish(node_b, "chat", TestMessages.encode!(msg2))

      # A responds
      msg3 = ChatMessage.new(id_a, "How's the mesh?", reply_to: id_b)
      :ok = Gossipsub.publish(node_a, "chat", TestMessages.encode!(msg3))
    end

    # 30 chat messages published
    Process.sleep(3_000)
    chat_received = drain_gossipsub_messages("chat")

    chats_decoded =
      Enum.flat_map(chat_received, fn data ->
        case ChatMessage.decode(data) do
          {:ok, chat} -> [chat]
          _ -> []
        end
      end)

    replies = Enum.count(chats_decoded, fn c -> c.reply_to != nil end)
    unique_chatters = Enum.uniq_by(chats_decoded, & &1.from) |> length()

    IO.puts(
      "[stress-msg] Phase 4: #{length(chats_decoded)} chat messages received, " <>
        "#{replies} replies, #{unique_chatters} unique chatters"
    )

    assert length(chats_decoded) >= 1,
           "at least 1 chat message should be received"

    for chat <- chats_decoded do
      assert is_binary(chat.from) and byte_size(chat.from) > 0
      assert is_binary(chat.text) and byte_size(chat.text) > 0
      assert is_integer(chat.timestamp)
    end

    # ── Phase 5: Churn during messaging ──────────────────────────
    IO.puts("[stress-msg] Phase 5: Churn during active messaging...")

    # Kill 10 random nodes
    churn_victims = Enum.take_random(nodes, 10)
    surviving_nodes = all_nodes -- churn_victims
    for node <- churn_victims, do: Node.stop(node)

    IO.puts("[stress-msg]   #{length(churn_victims)} nodes departed")
    Process.sleep(2_000)

    # 10 new nodes join
    newcomers =
      Enum.map(1..10, fn _i ->
        {:ok, node} = start_test_node(enable_mdns: true, gossipsub_topics: topics)
        :ok = Node.dial(node, seed_multiaddr)
        node
      end)

    Process.sleep(5_000)

    # Newcomers listen and publish
    for node <- newcomers, do: Gossipsub.register_handler(node)

    newcomer_ids =
      Map.new(newcomers, fn node ->
        {:ok, id} = Node.peer_id(node)
        {node, to_string(id)}
      end)

    for {node, nid} <- newcomer_ids do
      # Each newcomer announces itself with a sensor reading
      reading = SensorReading.new(nid, "heartbeat", 1.0, "alive", sequence: 1)
      :ok = Gossipsub.publish(node, "sensors", TestMessages.encode!(reading))

      # And announces a block
      block = BlockAnnouncement.new(nid, 999, tx_count: 0)
      :ok = Gossipsub.publish(node, "blocks", TestMessages.encode!(block))
    end

    Process.sleep(3_000)

    post_churn_sensor = drain_gossipsub_messages("sensors")
    post_churn_blocks = drain_gossipsub_messages("blocks")

    heartbeats =
      Enum.flat_map(post_churn_sensor, fn data ->
        case SensorReading.decode(data) do
          {:ok, %SensorReading{sensor: "heartbeat"} = r} -> [r]
          _ -> []
        end
      end)

    newcomer_blocks =
      Enum.flat_map(post_churn_blocks, fn data ->
        case BlockAnnouncement.decode(data) do
          {:ok, %BlockAnnouncement{height: 999} = b} -> [b]
          _ -> []
        end
      end)

    IO.puts(
      "[stress-msg] Phase 5: #{length(heartbeats)} heartbeats, " <>
        "#{length(newcomer_blocks)} newcomer blocks received after churn"
    )

    # ── Phase 6: Final summary ───────────────────────────────────
    final_alive = surviving_nodes ++ newcomers

    final_connected =
      Enum.count(final_alive, fn node ->
        {:ok, peers} = Node.connected_peers(node)
        length(peers) >= 1
      end)

    total_messages =
      length(blocks_decoded) + length(readings_decoded) + length(chats_decoded) +
        length(heartbeats) + length(newcomer_blocks)

    IO.puts("\n[stress-msg] ═══ Final Summary ═══")
    IO.puts("[stress-msg] Nodes alive:      #{length(final_alive)}")
    IO.puts("[stress-msg] Nodes connected:  #{final_connected}/#{length(final_alive)}")
    IO.puts("[stress-msg] Total messages:   #{total_messages}")
    IO.puts("[stress-msg]   Blocks:         #{length(blocks_decoded)}")
    IO.puts("[stress-msg]   Sensor readings: #{length(readings_decoded)}")
    IO.puts("[stress-msg]   Chat messages:   #{length(chats_decoded)}")
    IO.puts("[stress-msg]   Post-churn:      #{length(heartbeats) + length(newcomer_blocks)}")
    IO.puts("[stress-msg] ═══════════════════")

    assert total_messages >= 5,
           "at least 5 structured messages should have been received across all topics"

    assert final_connected >= length(final_alive) * 0.8,
           "at least 80% of final nodes should be connected, got #{final_connected}/#{length(final_alive)}"

    # ── Cleanup ──────────────────────────────────────────────────
    IO.puts("[stress-msg] Cleanup: stopping #{length(final_alive)} nodes...")

    final_alive
    |> Enum.chunk_every(20)
    |> Enum.each(fn batch ->
      Enum.each(batch, &Node.stop/1)
      Process.sleep(200)
    end)

    IO.puts("[stress-msg] Done.")
  end

  # ── Helpers ──────────────────────────────────────────────────────

  # Drains all gossipsub messages from the mailbox for a given topic.
  # Returns a list of raw data binaries.
  defp drain_gossipsub_messages(topic) do
    drain_gossipsub_messages(topic, [])
  end

  defp drain_gossipsub_messages(topic, acc) do
    receive do
      {:libp2p, :gossipsub_message, %GossipsubMessage{topic: msg_topic, data: data}} ->
        if msg_topic == topic or String.contains?(msg_topic, topic) do
          drain_gossipsub_messages(topic, [data | acc])
        else
          drain_gossipsub_messages(topic, acc)
        end
    after
      0 -> Enum.reverse(acc)
    end
  end
end
