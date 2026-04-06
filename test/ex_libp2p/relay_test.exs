defmodule ExLibp2p.RelayTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.{Node, Relay}

  setup do
    {:ok, node} =
      Node.start_link(
        native_module: ExLibp2p.Native.Mock,
        listen_addrs: ["/ip4/127.0.0.1/tcp/0"],
        enable_relay: true
      )

    %{node: node}
  end

  describe "listen_via_relay/2" do
    test "requests relay reservation", %{node: node} do
      assert :ok =
               Relay.listen_via_relay(
                 node,
                 "/ip4/1.2.3.4/tcp/4001/p2p/12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"
               )
    end
  end

  describe "register_handler/1" do
    test "registers for relay and NAT events", %{node: node} do
      assert :ok = Relay.register_handler(node)
    end
  end
end
