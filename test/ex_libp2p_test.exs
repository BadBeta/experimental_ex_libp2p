defmodule ExLibp2pTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, node} =
      ExLibp2p.Node.start_link(
        native_module: ExLibp2p.Native.Mock,
        listen_addrs: ["/ip4/127.0.0.1/tcp/0"]
      )

    %{node: node}
  end

  describe "peer_id/1" do
    test "delegates to Node", %{node: node} do
      assert {:ok, %ExLibp2p.PeerId{}} = ExLibp2p.peer_id(node)
    end
  end

  describe "connected_peers/1" do
    test "delegates to Node", %{node: node} do
      assert {:ok, []} = ExLibp2p.connected_peers(node)
    end
  end

  describe "dial/2" do
    test "delegates to Node", %{node: node} do
      assert :ok =
               ExLibp2p.dial(
                 node,
                 "/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"
               )
    end
  end

  describe "publish/3" do
    test "delegates to Gossipsub", %{node: node} do
      assert :ok = ExLibp2p.publish(node, "topic", "data")
    end
  end

  describe "subscribe/2" do
    test "delegates to Gossipsub", %{node: node} do
      assert :ok = ExLibp2p.subscribe(node, "topic")
    end
  end
end
