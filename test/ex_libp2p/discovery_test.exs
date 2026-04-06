defmodule ExLibp2p.DiscoveryTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.Discovery
  alias ExLibp2p.Node

  setup do
    {:ok, node} =
      Node.start_link(
        native_module: ExLibp2p.Native.Mock,
        listen_addrs: ["/ip4/127.0.0.1/tcp/0"]
      )

    %{node: node}
  end

  describe "register_handler/1" do
    test "registers for peer discovery events", %{node: node} do
      assert :ok = Discovery.register_handler(node)
    end
  end

  describe "bootstrap/2" do
    test "dials bootstrap peers and starts DHT bootstrap", %{node: node} do
      peers = [
        "/ip4/104.131.131.82/tcp/4001/p2p/12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"
      ]

      assert {:ok, [:ok]} = Discovery.bootstrap(node, peers)
    end

    test "returns ok with empty bootstrap list", %{node: node} do
      assert :ok = Discovery.bootstrap(node, [])
    end
  end
end
