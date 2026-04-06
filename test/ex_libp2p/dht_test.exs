defmodule ExLibp2p.DHTTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.{DHT, Node, PeerId}

  setup do
    {:ok, node} =
      Node.start_link(
        native_module: ExLibp2p.Native.Mock,
        listen_addrs: ["/ip4/127.0.0.1/tcp/0"]
      )

    %{node: node}
  end

  describe "put_record/3" do
    test "stores a key-value pair in the DHT", %{node: node} do
      assert :ok = DHT.put_record(node, "my-key", "my-value")
    end
  end

  describe "get_record/2" do
    test "initiates a DHT lookup", %{node: node} do
      assert :ok = DHT.get_record(node, "my-key")
    end
  end

  describe "find_peer/2" do
    test "initiates a peer lookup", %{node: node} do
      peer_id = PeerId.new!("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")
      assert :ok = DHT.find_peer(node, peer_id)
    end
  end

  describe "provide/2" do
    test "advertises as a content provider", %{node: node} do
      assert :ok = DHT.provide(node, "content-key")
    end
  end

  describe "find_providers/2" do
    test "finds providers for a key", %{node: node} do
      assert :ok = DHT.find_providers(node, "content-key")
    end
  end

  describe "bootstrap/1" do
    test "triggers DHT bootstrap", %{node: node} do
      assert :ok = DHT.bootstrap(node)
    end
  end

  describe "register_handler/1" do
    test "registers for DHT query results", %{node: node} do
      assert :ok = DHT.register_handler(node)
    end
  end
end
