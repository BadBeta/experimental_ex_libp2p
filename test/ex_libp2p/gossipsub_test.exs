defmodule ExLibp2p.GossipsubTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.Gossipsub
  alias ExLibp2p.Node

  setup do
    {:ok, node} =
      Node.start_link(
        native_module: ExLibp2p.Native.Mock,
        listen_addrs: ["/ip4/127.0.0.1/tcp/0"]
      )

    %{node: node}
  end

  describe "subscribe/2" do
    test "subscribes to a topic", %{node: node} do
      assert :ok = Gossipsub.subscribe(node, "my-topic")
    end
  end

  describe "unsubscribe/2" do
    test "unsubscribes from a topic", %{node: node} do
      :ok = Gossipsub.subscribe(node, "my-topic")
      assert :ok = Gossipsub.unsubscribe(node, "my-topic")
    end
  end

  describe "publish/3" do
    test "publishes string data", %{node: node} do
      assert :ok = Gossipsub.publish(node, "my-topic", "hello")
    end

    test "publishes binary data", %{node: node} do
      assert :ok = Gossipsub.publish(node, "my-topic", <<1, 2, 3, 4>>)
    end

    test "publishes JSON-encoded data", %{node: node} do
      data = Jason.encode!(%{type: "greeting", msg: "hello"})
      assert :ok = Gossipsub.publish(node, "my-topic", data)
    end
  end

  describe "register_handler/2" do
    test "registers for gossipsub messages", %{node: node} do
      assert :ok = Gossipsub.register_handler(node)
    end
  end
end
