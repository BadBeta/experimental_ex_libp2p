defmodule ExLibp2p.Gossipsub do
  @moduledoc """
  GossipSub publish-subscribe messaging.

  GossipSub is a topic-based pub/sub protocol that uses mesh networking and
  gossip for efficient message delivery. This module provides the public API
  for subscribing to topics, publishing messages, and receiving messages.

  ## Usage

      # Subscribe and register for messages
      :ok = ExLibp2p.Gossipsub.subscribe(node, "my-topic")
      :ok = ExLibp2p.Gossipsub.register_handler(node)

      # Publish a message
      :ok = ExLibp2p.Gossipsub.publish(node, "my-topic", "hello world")

      # Receive in handle_info:
      # {:libp2p, :gossipsub_message, %ExLibp2p.Node.Event.GossipsubMessage{}}

  """

  alias ExLibp2p.PeerId

  import ExLibp2p.Call, only: [safe_call: 2]

  @doc "Subscribes to a GossipSub topic."
  @spec subscribe(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def subscribe(node, topic) when is_binary(topic) do
    result = safe_call(node, {:subscribe, topic})

    :telemetry.execute(
      [:ex_libp2p, :gossipsub, :subscribe],
      %{count: 1},
      %{topic: topic, result: result_tag(result)}
    )

    result
  end

  @doc "Unsubscribes from a GossipSub topic."
  @spec unsubscribe(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def unsubscribe(node, topic) when is_binary(topic) do
    result = safe_call(node, {:unsubscribe, topic})

    :telemetry.execute(
      [:ex_libp2p, :gossipsub, :unsubscribe],
      %{count: 1},
      %{topic: topic, result: result_tag(result)}
    )

    result
  end

  @doc """
  Publishes binary data to a GossipSub topic.

  Data must be a binary. For structured data, encode with `Jason.encode!/1`
  or another serializer before publishing.
  """
  @spec publish(GenServer.server(), String.t(), binary()) :: :ok | {:error, term()}
  def publish(node, topic, data) when is_binary(topic) and is_binary(data) do
    :telemetry.span(
      [:ex_libp2p, :gossipsub, :publish],
      %{topic: topic, size: byte_size(data)},
      fn ->
        result = safe_call(node, {:publish, topic, data})
        {result, %{result: result_tag(result)}}
      end
    )
  end

  @doc """
  Registers the calling process to receive GossipSub messages.

  Messages arrive as `{:libp2p, :gossipsub_message, %ExLibp2p.Node.Event.GossipsubMessage{}}`.
  """
  @spec register_handler(GenServer.server(), pid()) :: :ok
  def register_handler(node, pid \\ self()) do
    safe_call(node, {:register_handler, :gossipsub_message, pid})
  end

  @doc "Returns the peers in the mesh for a specific topic."
  @spec mesh_peers(GenServer.server(), String.t()) ::
          {:ok, [PeerId.t()]} | {:error, term()}
  def mesh_peers(node, topic) when is_binary(topic) do
    case safe_call(node, {:gossipsub_mesh_peers, topic}) do
      {:ok, peers} -> {:ok, Enum.map(peers, &PeerId.new!/1)}
      {:error, _} = error -> error
    end
  end

  @doc "Returns all known GossipSub peers (mesh + non-mesh)."
  @spec all_peers(GenServer.server()) :: {:ok, [PeerId.t()]} | {:error, term()}
  def all_peers(node) do
    case safe_call(node, :gossipsub_all_peers) do
      {:ok, peers} -> {:ok, Enum.map(peers, &PeerId.new!/1)}
      {:error, _} = error -> error
    end
  end

  @doc "Returns the peer score for a specific peer (requires peer scoring enabled)."
  @spec peer_score(GenServer.server(), PeerId.t()) :: {:ok, float()} | {:error, term()}
  def peer_score(node, %PeerId{id: peer_id_str}) do
    safe_call(node, {:gossipsub_peer_score, peer_id_str})
  end

  defp result_tag(:ok), do: :ok
  defp result_tag({:ok, _}), do: :ok
  defp result_tag({:error, _}), do: :error
  defp result_tag(_), do: :unknown
end
