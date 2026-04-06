defmodule ExLibp2p.OTP.Distribution.Server do
  @moduledoc """
  Handles inbound OTP distribution requests from remote peers.

  Listens for request-response inbound requests, deserializes them,
  dispatches to locally registered GenServers, and sends back the reply.

  ## Usage

  Add to your supervision tree:

      children = [
        {ExLibp2p.Node, listen_addrs: ["/ip4/0.0.0.0/tcp/0"]},
        {ExLibp2p.OTP.Distribution.Server, node: MyApp.P2PNode}
      ]

  The server automatically registers for inbound request events
  and responds to remote `call`, `cast`, and `send` requests.
  """

  use GenServer
  require Logger

  alias ExLibp2p.{Node, RequestResponse}
  alias ExLibp2p.Node.Event
  alias ExLibp2p.OTP.Distribution

  @doc "Starts the distribution server linked to the caller."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {gen_opts, server_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, server_opts, gen_opts)
  end

  @impl true
  def init(opts) do
    node = Keyword.fetch!(opts, :node)

    # Register to receive inbound request-response events
    RequestResponse.register_handler(node)

    Logger.info("[ExLibp2p.OTP.Distribution.Server] Started, serving requests for #{inspect(node)}")

    {:ok, %{node: node}}
  end

  @impl true
  def handle_info(
        {:libp2p, :inbound_request, %Event.InboundRequest{channel_id: channel_id, data: data}},
        state
      ) do
    case Distribution.decode(data) do
      {:ok, request} ->
        {:ok, response} = Distribution.handle_remote_request(request)
        RequestResponse.send_response(state.node, channel_id, response)

      {:error, :invalid_message} ->
        Logger.warning("[ExLibp2p.OTP.Distribution.Server] Received invalid message, ignoring")
        response = Distribution.encode({:error, :invalid_message})
        RequestResponse.send_response(state.node, channel_id, response)
    end

    {:noreply, state}
  end

  # Ignore outbound response events (those go to the caller)
  def handle_info({:libp2p, :outbound_response, _}, state), do: {:noreply, state}

  def handle_info(msg, state) do
    Logger.debug("[ExLibp2p.OTP.Distribution.Server] Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
end
