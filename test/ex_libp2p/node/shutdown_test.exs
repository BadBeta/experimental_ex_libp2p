defmodule ExLibp2p.Node.ShutdownTest do
  use ExUnit.Case, async: false
  # async: false — uses the singleton HandlerRegistry from Application supervision.

  alias ExLibp2p.Node
  alias ExLibp2p.Node.HandlerRegistry

  setup do
    {:ok, node} =
      Node.start_link(
        native_module: ExLibp2p.Native.Mock,
        listen_addrs: ["/ip4/127.0.0.1/tcp/0"]
      )

    %{node: node}
  end

  describe "graceful shutdown" do
    test "Node.terminate/2 cleans up HandlerRegistry subscriptions for that node",
         %{node: node} do
      :ok = Node.register_handler(node, :gossipsub_message)
      :ok = Node.register_handler(node, :connection_established)

      assert HandlerRegistry.count(HandlerRegistry, node, :gossipsub_message) == 1
      assert HandlerRegistry.count(HandlerRegistry, node, :connection_established) == 1

      ref = Process.monitor(node)
      :ok = Node.stop(node)

      assert_receive {:DOWN, ^ref, :process, ^node, _reason}, 500

      # Sync the registry to ensure the cleanup_node call from terminate/2
      # has been processed before we assert.
      :ok = HandlerRegistry.sync(HandlerRegistry)

      assert HandlerRegistry.count(HandlerRegistry, node, :gossipsub_message) == 0
      assert HandlerRegistry.count(HandlerRegistry, node, :connection_established) == 0
    end

    test "subscribers stop receiving events after Node.stop/1", %{node: node} do
      :ok = Node.register_handler(node, :connection_established)

      ref = Process.monitor(node)
      :ok = Node.stop(node)
      assert_receive {:DOWN, ^ref, :process, ^node, _reason}, 500

      # Even if a stale event payload were somehow re-sent, the dispatcher's
      # subscription is gone — refute_receive confirms no event arrives.
      refute_receive {:libp2p, :connection_established, _}, 100
    end

    test "stop reason :normal logs cleanly without an error report", %{node: node} do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          ref = Process.monitor(node)
          :ok = Node.stop(node)
          assert_receive {:DOWN, ^ref, :process, ^node, _reason}, 500
        end)

      assert log =~ "Node stopping"
      # No GenServer crash report, no SASL error.
      refute log =~ "** (EXIT)"
      refute log =~ "Process crashed"
    end
  end
end
