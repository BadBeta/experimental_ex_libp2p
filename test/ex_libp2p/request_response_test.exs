defmodule ExLibp2p.RequestResponseTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.{Node, PeerId, RequestResponse}
  alias ExLibp2p.Node.Event

  setup do
    {:ok, node} =
      Node.start_link(
        native_module: ExLibp2p.Native.Mock,
        listen_addrs: ["/ip4/127.0.0.1/tcp/0"]
      )

    %{node: node}
  end

  describe "send_request/3" do
    test "sends a request to a peer", %{node: node} do
      peer_id = PeerId.new!("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")
      assert {:ok, _request_id} = RequestResponse.send_request(node, peer_id, "ping")
    end
  end

  describe "send_response/3" do
    test "sends a response for a request", %{node: node} do
      assert :ok = RequestResponse.send_response(node, "channel-1", "pong")
    end
  end

  describe "register_handler/1" do
    test "registers for request-response events", %{node: node} do
      assert :ok = RequestResponse.register_handler(node)
    end
  end

  describe "event dispatch" do
    test "dispatches inbound request events", %{node: node} do
      :ok = RequestResponse.register_handler(node)

      raw =
        {:inbound_request, "req-1", "channel-1",
         "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN", <<1, 2, 3>>}

      send(node, {:libp2p_event, raw})

      assert_receive {:libp2p, :inbound_request,
                      %Event.InboundRequest{
                        request_id: "req-1",
                        channel_id: "channel-1",
                        data: <<1, 2, 3>>
                      }},
                     1000
    end

    test "dispatches outbound response events", %{node: node} do
      :ok = RequestResponse.register_handler(node)

      raw =
        {:outbound_response, "req-1", "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN",
         <<4, 5, 6>>}

      send(node, {:libp2p_event, raw})

      assert_receive {:libp2p, :outbound_response,
                      %Event.OutboundResponse{
                        request_id: "req-1",
                        data: <<4, 5, 6>>
                      }},
                     1000
    end
  end
end
