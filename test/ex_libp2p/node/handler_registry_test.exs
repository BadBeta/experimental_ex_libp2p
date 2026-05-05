defmodule ExLibp2p.Node.HandlerRegistryTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.Node.HandlerRegistry

  setup do
    # Each test gets its own isolated registry so tests can run async without
    # bleeding registrations across the singleton in production app supervision.
    pid = start_supervised!({HandlerRegistry, name: :"hr_#{System.unique_integer([:positive])}"})
    %{registry: pid}
  end

  # Stand-in for a Node pid — any pid is fine for the registration key, the
  # registry doesn't dispatch back to it. Block on `receive` (never matches in
  # these tests) instead of sleeping so the process stays alive without a
  # timer.
  defp fake_node,
    do:
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

  defp long_lived,
    do:
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

  describe "register/4" do
    test "registers a pid for a {node, event_type} pair", %{registry: registry} do
      node = fake_node()
      assert :ok = HandlerRegistry.register(registry, node, :peer_discovered, self())
      assert HandlerRegistry.count(registry, node, :peer_discovered) == 1
    end

    test "is idempotent — re-registering same {node, event_type, pid} is a no-op",
         %{registry: registry} do
      node = fake_node()
      assert :ok = HandlerRegistry.register(registry, node, :peer_discovered, self())
      assert :ok = HandlerRegistry.register(registry, node, :peer_discovered, self())
      assert :ok = HandlerRegistry.register(registry, node, :peer_discovered, self())
      assert HandlerRegistry.count(registry, node, :peer_discovered) == 1
    end

    test "isolates registrations across different node pids", %{registry: registry} do
      node_a = fake_node()
      node_b = fake_node()
      assert :ok = HandlerRegistry.register(registry, node_a, :peer_discovered, self())
      assert HandlerRegistry.count(registry, node_b, :peer_discovered) == 0
    end

    test "registers multiple distinct pids for same event_type", %{registry: registry} do
      node = fake_node()
      sub_a = long_lived()
      sub_b = long_lived()
      assert :ok = HandlerRegistry.register(registry, node, :gossipsub_message, sub_a)
      assert :ok = HandlerRegistry.register(registry, node, :gossipsub_message, sub_b)
      assert HandlerRegistry.count(registry, node, :gossipsub_message) == 2
    end
  end

  describe "unregister/4" do
    test "removes the registration", %{registry: registry} do
      node = fake_node()
      :ok = HandlerRegistry.register(registry, node, :peer_discovered, self())
      assert :ok = HandlerRegistry.unregister(registry, node, :peer_discovered, self())
      assert HandlerRegistry.count(registry, node, :peer_discovered) == 0
    end

    test "unregistering a non-existent pid is a no-op", %{registry: registry} do
      node = fake_node()
      assert :ok = HandlerRegistry.unregister(registry, node, :peer_discovered, self())
    end
  end

  describe "dispatch/3" do
    test "delivers the event to all registered subscribers", %{registry: registry} do
      node = fake_node()
      :ok = HandlerRegistry.register(registry, node, :gossipsub_message, self())

      :ok = HandlerRegistry.dispatch(registry, node, :gossipsub_message, %{topic: "alpha"})

      assert_receive {:libp2p, :gossipsub_message, %{topic: "alpha"}}, 500
    end

    test "does NOT deliver to subscribers of a different node", %{registry: registry} do
      node_a = fake_node()
      node_b = fake_node()
      :ok = HandlerRegistry.register(registry, node_a, :gossipsub_message, self())

      :ok = HandlerRegistry.dispatch(registry, node_b, :gossipsub_message, %{topic: "alpha"})

      refute_receive {:libp2p, :gossipsub_message, _}, 100
    end

    test "is a no-op when no subscribers are registered", %{registry: registry} do
      node = fake_node()
      assert :ok = HandlerRegistry.dispatch(registry, node, :gossipsub_message, %{})
    end
  end

  describe "automatic cleanup on subscriber death" do
    test "removes a dead subscriber from the registry", %{registry: registry} do
      node = fake_node()
      sub = long_lived()
      :ok = HandlerRegistry.register(registry, node, :peer_discovered, sub)
      assert HandlerRegistry.count(registry, node, :peer_discovered) == 1

      Process.exit(sub, :kill)
      # Wait for the :DOWN message to be processed
      :ok = HandlerRegistry.sync(registry)

      assert HandlerRegistry.count(registry, node, :peer_discovered) == 0
    end
  end

  describe "cleanup_node/1" do
    test "removes all registrations for a given node", %{registry: registry} do
      node = fake_node()
      :ok = HandlerRegistry.register(registry, node, :peer_discovered, self())
      :ok = HandlerRegistry.register(registry, node, :gossipsub_message, self())
      assert HandlerRegistry.count(registry, node, :peer_discovered) == 1
      assert HandlerRegistry.count(registry, node, :gossipsub_message) == 1

      :ok = HandlerRegistry.cleanup_node(registry, node)

      assert HandlerRegistry.count(registry, node, :peer_discovered) == 0
      assert HandlerRegistry.count(registry, node, :gossipsub_message) == 0
    end
  end

  describe "format_status/1" do
    test "summarizes state to counts; does not dump full handler/monitor maps",
         %{registry: registry} do
      node = fake_node()
      :ok = HandlerRegistry.register(registry, node, :peer_discovered, self())
      {:status, _pid, _module, status_sections} = :sys.get_status(registry)

      # The last section is `[..., data: [{~c"State", state_term}]]` — find
      # the State entry without depending on the exact section layout
      # (which differs between OTP versions).
      state_term =
        status_sections
        |> List.last()
        |> Enum.flat_map(fn
          {:data, kvs} -> kvs
          _ -> []
        end)
        |> Enum.find_value(fn
          {~c"State", v} -> v
          _ -> nil
        end)

      assert is_map(state_term)
      assert is_integer(state_term.subscriptions)
      assert is_integer(state_term.monitors)
    end
  end
end
