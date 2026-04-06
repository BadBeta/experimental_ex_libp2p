defmodule ExLibp2p.RequestResponse do
  @moduledoc """
  Request-response RPC protocol.

  Provides point-to-point request/response communication between peers.
  Each request opens a new substream, sends the payload, and waits for
  a response. Uses CBOR encoding at the transport layer — Elixir handles
  serialization (pass binary data).

  ## Usage

      # Register to receive inbound requests
      :ok = ExLibp2p.RequestResponse.register_handler(node)

      # Send a request to a peer
      {:ok, request_id} = ExLibp2p.RequestResponse.send_request(node, peer_id, payload)

      # Handle inbound requests in handle_info:
      # {:libp2p, :inbound_request, %ExLibp2p.Node.Event.InboundRequest{}}

      # Send a response using the channel_id from the inbound request
      :ok = ExLibp2p.RequestResponse.send_response(node, channel_id, response_data)

      # Handle responses in handle_info:
      # {:libp2p, :outbound_response, %ExLibp2p.Node.Event.OutboundResponse{}}

  """

  alias ExLibp2p.{Node, PeerId}

  @doc """
  Sends a request to a peer. Returns `{:ok, request_id}` for correlation.

  The request_id can be used to match the response event.
  """
  @spec send_request(GenServer.server(), PeerId.t(), binary()) ::
          {:ok, String.t()} | {:error, term()}
  def send_request(node, %PeerId{id: peer_id_str}, data) when is_binary(data) do
    GenServer.call(node, {:rpc_send_request, peer_id_str, data})
  end

  @doc """
  Sends a response for an inbound request.

  Use the `channel_id` from the `InboundRequest` event.
  """
  @spec send_response(GenServer.server(), String.t(), binary()) :: :ok | {:error, term()}
  def send_response(node, channel_id, data) when is_binary(channel_id) and is_binary(data) do
    GenServer.call(node, {:rpc_send_response, channel_id, data})
  end

  @doc """
  Registers the calling process to receive request-response events.

  Events:
  - `{:libp2p, :inbound_request, %ExLibp2p.Node.Event.InboundRequest{}}`
  - `{:libp2p, :outbound_response, %ExLibp2p.Node.Event.OutboundResponse{}}`
  """
  @spec register_handler(GenServer.server(), pid()) :: :ok
  def register_handler(node, pid \\ self()) do
    :ok = Node.register_handler(node, :inbound_request, pid)
    Node.register_handler(node, :outbound_response, pid)
  end
end
