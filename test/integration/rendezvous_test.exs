defmodule ExLibp2p.Integration.RendezvousTest do
  @moduledoc "End-to-end tests for rendezvous namespace discovery."
  use ExLibp2p.NifCase, async: false

  alias ExLibp2p.{Node, Rendezvous}

  @tag :integration
  test "register, discover, and unregister via rendezvous server" do
    # Start a node that acts as rendezvous server
    {:ok, server} = start_test_node(enable_rendezvous_server: true)
    Process.sleep(200)
    {:ok, [server_addr | _]} = Node.listening_addrs(server)
    {:ok, server_id} = Node.peer_id(server)
    server_multiaddr = "#{server_addr}/p2p/#{server_id}"

    # Start a client node and connect to the server
    {:ok, client} = start_test_node(enable_rendezvous_client: true)
    Node.dial(client, server_multiaddr)
    Process.sleep(1_000)

    # Register, discover, unregister — all should succeed without crashing
    :ok = Rendezvous.register(client, "my-service", server_id, 3600)
    :ok = Rendezvous.discover(client, "my-service", server_id)
    :ok = Rendezvous.unregister(client, "my-service", server_id)

    # Nodes should be healthy
    assert {:ok, _} = Node.peer_id(server)
    assert {:ok, _} = Node.peer_id(client)

    Node.stop(server)
    Node.stop(client)
  end

  @tag :integration
  test "register_handler for discovery events" do
    {:ok, node} = start_test_node(enable_rendezvous_client: true)
    :ok = Rendezvous.register_handler(node)
    assert {:ok, _} = Node.peer_id(node)
    Node.stop(node)
  end
end
