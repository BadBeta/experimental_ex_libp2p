defmodule ExLibp2p.Integration.RequestResponseTest do
  @moduledoc "End-to-end tests for request-response RPC between real nodes."
  use ExLibp2p.NifCase, async: false

  alias ExLibp2p.{Node, RequestResponse}
  alias ExLibp2p.Node.Event

  @tag :integration
  test "send_request returns a request ID" do
    {:ok, node_a} = start_test_node()
    {:ok, node_b} = start_test_node()

    # Connect them
    Process.sleep(200)
    {:ok, [addr | _]} = Node.listening_addrs(node_a)
    {:ok, peer_id_a} = Node.peer_id(node_a)
    Node.dial(node_b, "#{addr}/p2p/#{peer_id_a}")
    Process.sleep(500)

    # Send request from B to A
    {:ok, request_id} = RequestResponse.send_request(node_b, peer_id_a, "ping")
    assert is_binary(request_id)
    assert byte_size(request_id) > 0

    Node.stop(node_a)
    Node.stop(node_b)
  end

  @tag :integration
  test "inbound request arrives with channel_id and data" do
    {:ok, node_a} = start_test_node()
    {:ok, node_b} = start_test_node()

    # Register A for inbound requests
    RequestResponse.register_handler(node_a)

    # Connect
    Process.sleep(200)
    {:ok, [addr_a | _]} = Node.listening_addrs(node_a)
    {:ok, peer_id_a} = Node.peer_id(node_a)
    Node.dial(node_b, "#{addr_a}/p2p/#{peer_id_a}")
    Process.sleep(1_000)

    # B sends request to A
    {:ok, _req_id} = RequestResponse.send_request(node_b, peer_id_a, "hello-rpc")

    assert_receive {:libp2p, :inbound_request,
                    %Event.InboundRequest{
                      request_id: req_id,
                      channel_id: ch_id,
                      data: data
                    }},
                   5_000

    assert is_binary(req_id)
    assert is_binary(ch_id)
    assert data == "hello-rpc"

    Node.stop(node_a)
    Node.stop(node_b)
  end

  @tag :integration
  test "send_response delivers reply to requester" do
    {:ok, server} = start_test_node()
    {:ok, client} = start_test_node()

    # Server listens for requests, client listens for responses
    RequestResponse.register_handler(server)
    RequestResponse.register_handler(client)

    Process.sleep(200)
    {:ok, [addr | _]} = Node.listening_addrs(server)
    {:ok, server_id} = Node.peer_id(server)
    Node.dial(client, "#{addr}/p2p/#{server_id}")
    Process.sleep(1_000)

    # Client sends request
    {:ok, _} = RequestResponse.send_request(client, server_id, "request-data")

    # Server receives inbound request
    assert_receive {:libp2p, :inbound_request, %Event.InboundRequest{channel_id: channel_id}},
                   5_000

    # Server sends response using the channel_id
    :ok = RequestResponse.send_response(server, channel_id, "response-data")

    # Client receives the response
    assert_receive {:libp2p, :outbound_response, %Event.OutboundResponse{data: response_data}},
                   5_000

    assert response_data == "response-data"

    Node.stop(server)
    Node.stop(client)
  end
end
