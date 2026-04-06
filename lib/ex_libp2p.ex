defmodule ExLibp2p do
  @moduledoc """
  Elixir wrapper for libp2p peer-to-peer networking.

  ExLibp2p provides an idiomatic Elixir API for building decentralized
  applications using the libp2p networking stack. It wraps the Rust
  `rust-libp2p` implementation via NIFs for production-grade performance.

  ## Quick Start

      # Start a node
      {:ok, node} = ExLibp2p.Node.start_link(
        listen_addrs: ["/ip4/0.0.0.0/tcp/0"],
        enable_mdns: true
      )

      # Get peer identity
      {:ok, peer_id} = ExLibp2p.peer_id(node)

      # Subscribe to a topic
      :ok = ExLibp2p.subscribe(node, "my-topic")

      # Publish a message
      :ok = ExLibp2p.publish(node, "my-topic", "hello network")

  ## Architecture

  ExLibp2p is organized into context modules:

  - `ExLibp2p.Node` — core node lifecycle and connectivity
  - `ExLibp2p.Gossipsub` — publish-subscribe messaging
  - `ExLibp2p.DHT` — distributed hash table operations
  - `ExLibp2p.Discovery` — peer discovery (mDNS, bootstrap)
  - `ExLibp2p.Health` — periodic health monitoring
  - `ExLibp2p.Telemetry` — observability event definitions

  This module provides convenience delegates to the most common operations.
  """

  alias ExLibp2p.Gossipsub
  alias ExLibp2p.Node

  @doc "Returns the node's peer ID."
  @spec peer_id(GenServer.server()) :: {:ok, ExLibp2p.PeerId.t()} | {:error, term()}
  defdelegate peer_id(node), to: Node

  @doc "Returns the list of currently connected peers."
  @spec connected_peers(GenServer.server()) :: {:ok, [ExLibp2p.PeerId.t()]} | {:error, term()}
  defdelegate connected_peers(node), to: Node

  @doc "Returns the addresses this node is listening on."
  @spec listening_addrs(GenServer.server()) :: {:ok, [String.t()]} | {:error, term()}
  defdelegate listening_addrs(node), to: Node

  @doc "Dials a peer at the given multiaddr."
  @spec dial(GenServer.server(), String.t()) :: :ok | {:error, term()}
  defdelegate dial(node, addr), to: Node

  @doc "Publishes data to a GossipSub topic."
  @spec publish(GenServer.server(), String.t(), binary()) :: :ok | {:error, term()}
  defdelegate publish(node, topic, data), to: Gossipsub

  @doc "Subscribes to a GossipSub topic."
  @spec subscribe(GenServer.server(), String.t()) :: :ok | {:error, term()}
  defdelegate subscribe(node, topic), to: Gossipsub

  @doc "Unsubscribes from a GossipSub topic."
  @spec unsubscribe(GenServer.server(), String.t()) :: :ok | {:error, term()}
  defdelegate unsubscribe(node, topic), to: Gossipsub

  @doc "Sends an RPC request to a peer."
  @spec send_request(GenServer.server(), ExLibp2p.PeerId.t(), binary()) ::
          {:ok, String.t()} | {:error, term()}
  defdelegate send_request(node, peer_id, data), to: ExLibp2p.RequestResponse

  @doc "Stops the node gracefully."
  @spec stop(GenServer.server()) :: :ok
  defdelegate stop(node), to: Node
end
