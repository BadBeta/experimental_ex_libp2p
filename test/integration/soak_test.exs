defmodule ExLibp2p.Integration.SoakTest do
  @moduledoc """
  Long-running soak test simulating extended uptime.

  Runs a network of nodes through many cycles of:
  - High-volume messaging (gossipsub broadcast + request-response)
  - Node churn (joins, graceful leaves, simulated crashes)
  - mDNS discovery of new arrivals
  - DHT operations under load

  After each cycle, measures BEAM memory and process count.
  The test asserts that resource usage stays bounded — no growth
  over time means no leaks.

  Run with:
      mix test --include soak --timeout 900000
  """
  use ExLibp2p.NifCase, async: false

  alias ExLibp2p.{DHT, Discovery, Gossipsub, Node, RequestResponse}
  alias ExLibp2p.Node.Event.GossipsubMessage

  @moduletag :integration
  @moduletag :soak
  @moduletag timeout: 3_600_000

  # Network size
  @backbone_count 30
  @batch_size 10
  # Churn per cycle
  @churn_per_cycle 5
  # Number of soak cycles — 50 is enough to surface slow leaks
  @cycles 50
  # Messages per cycle
  @messages_per_cycle 100
  # Max allowed memory growth after cleanup vs baseline.
  # Baseline is taken after initial mesh formation, so warmup is excluded.
  # A leak-free node under churn should stabilize — 20% headroom for GC timing.
  @max_memory_growth_factor 1.2
  # Max allowed process count growth — churn creates/destroys processes each cycle,
  # but net growth should be near zero. 50 allows for transient stragglers.
  @max_process_growth 50

  @tag :soak
  test "resource usage stays bounded under sustained load and churn" do
    topic = "soak-topic"

    # ── Bootstrap ────────────────────────────────────────────────
    IO.puts("\n[soak] Bootstrapping #{@backbone_count + 1} node network...")

    {:ok, seed} = start_test_node(enable_mdns: true, gossipsub_topics: [topic])
    Process.sleep(300)
    {:ok, [seed_addr | _]} = Node.listening_addrs(seed)
    {:ok, seed_id} = Node.peer_id(seed)
    seed_multiaddr = "#{seed_addr}/p2p/#{seed_id}"

    backbone =
      1..@backbone_count
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

    all_stable = [seed | backbone]

    # Wait for mesh formation
    IO.puts("[soak] Waiting for mesh formation...")
    Process.sleep(8_000)

    # Register gossipsub on seed to drain messages (prevent mailbox buildup)
    Gossipsub.register_handler(seed)

    # ── Baseline measurement ─────────────────────────────────────
    :erlang.garbage_collect()
    Process.sleep(500)
    baseline = take_measurement()

    IO.puts("[soak] Baseline: #{format_measurement(baseline)}")

    # ── Soak cycles ──────────────────────────────────────────────
    measurements = [baseline]
    churn_pool = []

    {final_measurements, final_churn_pool} =
      Enum.reduce(1..@cycles, {measurements, churn_pool}, fn cycle, {meas, pool} ->
        if rem(cycle, 10) == 1 or cycle == @cycles do
          IO.puts("\n[soak] ═══ Cycle #{cycle}/#{@cycles} ═══")
        end

        # Phase A: High-volume gossipsub messaging
        verbose = rem(cycle, 10) == 1 or cycle == @cycles

        if verbose do
          IO.puts("[soak]   Publishing #{@messages_per_cycle} gossipsub messages...")
        end

        publishers = Enum.take_random(all_stable, 10)

        for {pub_node, i} <- Enum.with_index(publishers) do
          for j <- 1..div(@messages_per_cycle, 10) do
            payload = "cycle-#{cycle}-msg-#{i * 100 + j}-#{:rand.uniform(999_999)}"
            Gossipsub.publish(pub_node, topic, payload)
          end
        end

        Process.sleep(500)

        # Drain the seed's mailbox to prevent buildup
        drained = drain_all_messages()
        if verbose, do: IO.puts("[soak]   Drained #{drained} messages from test process")

        # Phase B: Request-response traffic between random pairs
        if verbose,
          do: IO.puts("[soak]   Sending #{@churn_per_cycle * 2} request-response messages...")

        pairs = all_stable |> Enum.shuffle() |> Enum.chunk_every(2) |> Enum.take(@churn_per_cycle)

        for [a, b] <- pairs do
          {:ok, a_id} = Node.peer_id(a)
          {:ok, b_id} = Node.peer_id(b)
          # These may fail if peers aren't directly connected — that's ok
          RequestResponse.send_request(a, b_id, "ping-#{cycle}")
          RequestResponse.send_request(b, a_id, "pong-#{cycle}")
        end

        Process.sleep(300)
        drain_all_messages()

        # Phase C: DHT operations
        if verbose, do: IO.puts("[soak]   DHT put/get operations...")

        dht_node = Enum.random(all_stable)
        DHT.put_record(dht_node, "soak-key-#{cycle}", "soak-value-#{cycle}")
        DHT.get_record(dht_node, "soak-key-#{cycle}")

        Process.sleep(200)
        drain_all_messages()

        # Phase D: Graceful node departure
        if verbose, do: IO.puts("[soak]   #{@churn_per_cycle} nodes departing gracefully...")

        {leavers, _} = Enum.split(pool, min(@churn_per_cycle, length(pool)))
        for node <- leavers, Process.alive?(node), do: Node.stop(node)
        remaining_pool = pool -- leavers

        Process.sleep(500)

        # Phase E: Simulated crash (Process.exit with :kill)
        crash_count = min(2, length(remaining_pool))

        if crash_count > 0 do
          if verbose, do: IO.puts("[soak]   Simulating #{crash_count} node crashes...")
          {crash_victims, surviving_pool} = Enum.split(remaining_pool, crash_count)

          for node <- crash_victims, Process.alive?(node) do
            Process.exit(node, :kill)
          end

          Process.sleep(500)
          remaining_pool = surviving_pool
        else
          remaining_pool = remaining_pool
        end

        # Phase F: New nodes join via mDNS
        if verbose, do: IO.puts("[soak]   #{@churn_per_cycle} new nodes arriving (mDNS)...")

        new_nodes =
          Enum.map(1..@churn_per_cycle, fn _i ->
            {:ok, node} = start_test_node(enable_mdns: true, gossipsub_topics: [topic])
            node
          end)

        Process.sleep(3_000)

        # Phase G: Measurement
        :erlang.garbage_collect()
        Process.sleep(300)
        measurement = take_measurement()

        if verbose do
          memory_ratio = measurement.total_memory / baseline.total_memory
          process_growth = measurement.process_count - baseline.process_count

          IO.puts(
            "[soak]   #{format_measurement(measurement)} | " <>
              "#{Float.round(memory_ratio, 2)}x baseline, +#{process_growth} procs"
          )
        end

        {[measurement | meas], remaining_pool ++ new_nodes}
      end)

    # ── Cleanup churn pool ───────────────────────────────────────
    for node <- final_churn_pool, Process.alive?(node), do: Node.stop(node)
    Process.sleep(1_000)

    # ── Final measurement after cleanup ──────────────────────────
    :erlang.garbage_collect()
    Process.sleep(500)
    final = take_measurement()

    IO.puts("\n[soak] ═══ Final Results ═══")
    IO.puts("[soak] Baseline:  #{format_measurement(baseline)}")
    IO.puts("[soak] Final:     #{format_measurement(final)}")

    # ── Assertions ───────────────────────────────────────────────

    # Memory should not grow unboundedly
    # Compare against baseline (not the peak during churn)
    memory_ratio = final.total_memory / baseline.total_memory

    IO.puts(
      "[soak] Memory ratio (final/baseline): #{Float.round(memory_ratio, 2)}x " <>
        "(max allowed: #{@max_memory_growth_factor}x)"
    )

    assert memory_ratio <= @max_memory_growth_factor,
           "memory grew #{Float.round(memory_ratio, 2)}x from baseline " <>
             "(#{format_bytes(baseline.total_memory)} → #{format_bytes(final.total_memory)}), " <>
             "max allowed: #{@max_memory_growth_factor}x"

    # Process count should not grow unboundedly
    process_growth = final.process_count - baseline.process_count

    IO.puts("[soak] Process growth: #{process_growth} (max allowed: #{@max_process_growth})")

    assert process_growth <= @max_process_growth,
           "process count grew by #{process_growth} " <>
             "(#{baseline.process_count} → #{final.process_count}), " <>
             "max allowed: #{@max_process_growth}"

    # Linear regression on memory over time to detect steady growth (leak signature).
    # With 50 data points, a positive slope indicates a leak.
    # We use the second half of measurements (steady state, past warmup).
    all_meas = Enum.reverse(final_measurements)
    steady_state = Enum.drop(all_meas, div(length(all_meas), 2))

    if length(steady_state) >= 10 do
      memory_values = Enum.map(steady_state, & &1.total_memory)
      slope_per_cycle = linear_slope(memory_values)
      avg_memory = Enum.sum(memory_values) / length(memory_values)
      # Slope as percentage of average memory per cycle
      slope_pct = slope_per_cycle / avg_memory * 100

      IO.puts(
        "[soak] Memory slope (steady state): #{Float.round(slope_per_cycle / 1024, 1)}KB/cycle " <>
          "(#{Float.round(slope_pct, 3)}% of avg)"
      )

      # If memory grows more than 0.5% per cycle in steady state, that's a leak
      assert slope_pct < 0.5,
             "memory is growing #{Float.round(slope_pct, 3)}% per cycle in steady state — likely leak"

      # Also check process count slope
      proc_values = Enum.map(steady_state, & &1.process_count)
      proc_slope = linear_slope(proc_values)

      IO.puts("[soak] Process slope (steady state): #{Float.round(proc_slope, 2)}/cycle")

      assert proc_slope < 1.0,
             "process count is growing #{Float.round(proc_slope, 2)} per cycle — likely leak"

      # Binary memory is a common leak source (NIF-allocated binaries)
      bin_values = Enum.map(steady_state, & &1.binary_memory)
      bin_slope = linear_slope(bin_values)
      bin_slope_pct = bin_slope / max(Enum.sum(bin_values) / length(bin_values), 1) * 100

      IO.puts(
        "[soak] Binary mem slope: #{Float.round(bin_slope / 1024, 1)}KB/cycle " <>
          "(#{Float.round(bin_slope_pct, 3)}% of avg)"
      )

      assert bin_slope_pct < 1.0,
             "binary memory growing #{Float.round(bin_slope_pct, 3)}% per cycle — NIF binary leak?"
    end

    # ── Cleanup stable nodes ─────────────────────────────────────
    IO.puts("[soak] Cleanup: stopping #{length(all_stable)} stable nodes...")

    for node <- all_stable, Process.alive?(node) do
      Node.stop(node)
    end

    IO.puts("[soak] Done.")
  end

  # ── Measurement helpers ──────────────────────────────────────────

  defp take_measurement do
    memory = :erlang.memory()

    %{
      total_memory: memory[:total],
      process_memory: memory[:processes],
      binary_memory: memory[:binary],
      ets_memory: memory[:ets],
      atom_memory: memory[:atom],
      process_count: length(Process.list()),
      timestamp: System.monotonic_time(:millisecond)
    }
  end

  defp format_measurement(m) do
    "total=#{format_bytes(m.total_memory)} " <>
      "proc=#{format_bytes(m.process_memory)} " <>
      "bin=#{format_bytes(m.binary_memory)} " <>
      "ets=#{format_bytes(m.ets_memory)} " <>
      "procs=#{m.process_count}"
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes}B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)}KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)}MB"

  # Least-squares linear regression slope.
  # Given y values at equally-spaced x points, returns the slope (change per step).
  defp linear_slope(values) when length(values) < 2, do: 0.0

  defp linear_slope(values) do
    n = length(values)
    xs = Enum.to_list(0..(n - 1))
    ys = Enum.map(values, &(&1 / 1.0))

    sum_x = Enum.sum(xs)
    sum_y = Enum.sum(ys)
    sum_xy = xs |> Enum.zip(ys) |> Enum.map(fn {x, y} -> x * y end) |> Enum.sum()
    sum_x2 = xs |> Enum.map(&(&1 * &1)) |> Enum.sum()

    denom = n * sum_x2 - sum_x * sum_x

    if denom == 0, do: 0.0, else: (n * sum_xy - sum_x * sum_y) / denom
  end

  defp drain_all_messages do
    drain_all_messages(0)
  end

  defp drain_all_messages(count) do
    receive do
      {:libp2p, _, _} -> drain_all_messages(count + 1)
    after
      0 -> count
    end
  end
end
