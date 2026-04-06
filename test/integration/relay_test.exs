defmodule ExLibp2p.Integration.RelayTest do
  @moduledoc "End-to-end tests for relay and NAT traversal operations."
  use ExLibp2p.NifCase, async: false

  alias ExLibp2p.{Node, Relay}

  @tag :integration
  test "listen_via_relay accepts a relay address" do
    {:ok, node} = start_test_node(enable_relay: true)

    # This will attempt to listen via the relay — the relay won't exist
    # but the command should be accepted without crashing
    :ok =
      Relay.listen_via_relay(
        node,
        "/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN/p2p-circuit"
      )

    # Node should still be functional
    Process.sleep(500)
    assert {:ok, _} = Node.peer_id(node)

    Node.stop(node)
  end

  @tag :integration
  test "register_handler for NAT events" do
    {:ok, node} = start_test_node(enable_relay: true)

    :ok = Relay.register_handler(node)

    # Verify the node is healthy after registering for all NAT event types
    assert {:ok, _} = Node.peer_id(node)

    Node.stop(node)
  end
end
