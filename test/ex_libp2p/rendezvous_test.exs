defmodule ExLibp2p.RendezvousTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.{Node, PeerId, Rendezvous}

  @rendezvous_peer PeerId.new!("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")

  setup do
    {:ok, node} =
      Node.start_link(
        native_module: ExLibp2p.Native.Mock,
        listen_addrs: ["/ip4/127.0.0.1/tcp/0"],
        enable_rendezvous_client: true
      )

    %{node: node}
  end

  describe "register/4" do
    test "registers under a namespace at a rendezvous peer", %{node: node} do
      assert :ok = Rendezvous.register(node, "my-service", @rendezvous_peer, 3600)
    end

    test "uses default TTL", %{node: node} do
      assert :ok = Rendezvous.register(node, "my-service", @rendezvous_peer)
    end
  end

  describe "discover/3" do
    test "initiates namespace discovery at rendezvous peer", %{node: node} do
      assert :ok = Rendezvous.discover(node, "my-service", @rendezvous_peer)
    end
  end

  describe "unregister/3" do
    test "unregisters from a namespace", %{node: node} do
      assert :ok = Rendezvous.unregister(node, "my-service", @rendezvous_peer)
    end
  end

  describe "register_handler/1" do
    test "registers for discovery events", %{node: node} do
      assert :ok = Rendezvous.register_handler(node)
    end
  end
end
