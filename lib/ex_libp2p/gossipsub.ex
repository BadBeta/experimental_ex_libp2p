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

  alias ExLibp2p.{Node, PeerId}

  @doc "Subscribes to a GossipSub topic."
  @spec subscribe(GenServer.server(), String.t()) :: :ok | {:error, term()}
  defdelegate subscribe(node, topic), to: Node

  @doc "Unsubscribes from a GossipSub topic."
  @spec unsubscribe(GenServer.server(), String.t()) :: :ok | {:error, term()}
  defdelegate unsubscribe(node, topic), to: Node

  @doc """
  Publishes binary data to a GossipSub topic.

  Data must be a binary. For structured data, encode with `Jason.encode!/1`
  or another serializer before publishing.
  """
  @spec publish(GenServer.server(), String.t(), binary()) :: :ok | {:error, term()}
  defdelegate publish(node, topic, data), to: Node

  @doc """
  Registers the calling process to receive GossipSub messages.

  Messages arrive as `{:libp2p, :gossipsub_message, %ExLibp2p.Node.Event.GossipsubMessage{}}`.
  """
  @spec register_handler(GenServer.server(), pid()) :: :ok
  def register_handler(node, pid \\ self()),
    do: Node.register_handler(node, :gossipsub_message, pid)

  @doc "Returns the peers in the mesh for a specific topic."
  @spec mesh_peers(GenServer.server(), String.t()) ::
          {:ok, [PeerId.t()]} | {:error, term()}
  def mesh_peers(node, topic) when is_binary(topic) do
    with {:ok, peers} <- Node.gossipsub_mesh_peers(node, topic) do
      {:ok, Enum.map(peers, &PeerId.new!/1)}
    end
  end

  @doc "Returns all known GossipSub peers (mesh + non-mesh)."
  @spec all_peers(GenServer.server()) :: {:ok, [PeerId.t()]} | {:error, term()}
  def all_peers(node) do
    with {:ok, peers} <- Node.gossipsub_all_peers(node) do
      {:ok, Enum.map(peers, &PeerId.new!/1)}
    end
  end

  @doc "Returns the peer score for a specific peer (requires peer scoring enabled)."
  @spec peer_score(GenServer.server(), PeerId.t()) :: {:ok, float()} | {:error, term()}
  def peer_score(node, %PeerId{id: peer_id_str}) do
    Node.gossipsub_peer_score(node, peer_id_str)
  end
end
