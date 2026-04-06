defmodule ExLibp2p.OTP.Distribution.ServerTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.{Node, PeerId}
  alias ExLibp2p.Node.Event
  alias ExLibp2p.OTP.Distribution
  alias ExLibp2p.OTP.Distribution.Server, as: DistServer

  setup do
    {:ok, node} =
      Node.start_link(
        native_module: ExLibp2p.Native.Mock,
        listen_addrs: ["/ip4/127.0.0.1/tcp/0"]
      )

    {:ok, server} = DistServer.start_link(node: node)

    %{node: node, server: server}
  end

  test "dispatches inbound call to local GenServer", %{server: server} do
    {:ok, _} = Agent.start_link(fn -> :pong end, name: :dist_test_agent)

    # Simulate an inbound request arriving
    request_data = Distribution.encode({:call, :dist_test_agent, {:get, fn s -> s end}})

    inbound_event = %Event.InboundRequest{
      request_id: "req-1",
      channel_id: "ch-1",
      peer_id: PeerId.new!("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"),
      data: request_data
    }

    send(server, {:libp2p, :inbound_request, inbound_event})

    # Give the server time to process
    Process.sleep(100)

    # Server should still be alive
    assert Process.alive?(server)

    Agent.stop(:dist_test_agent)
  end

  test "handles request to nonexistent process gracefully", %{server: server} do
    request_data = Distribution.encode({:call, :nonexistent_dist_process, :ping})

    inbound_event = %Event.InboundRequest{
      request_id: "req-2",
      channel_id: "ch-2",
      peer_id: PeerId.new!("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"),
      data: request_data
    }

    send(server, {:libp2p, :inbound_request, inbound_event})
    Process.sleep(100)

    assert Process.alive?(server)
  end

  test "handles invalid message data gracefully", %{server: server} do
    inbound_event = %Event.InboundRequest{
      request_id: "req-3",
      channel_id: "ch-3",
      peer_id: PeerId.new!("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"),
      data: <<0, 1, 2, 3, 4>>
    }

    send(server, {:libp2p, :inbound_request, inbound_event})
    Process.sleep(100)

    assert Process.alive?(server)
  end
end
