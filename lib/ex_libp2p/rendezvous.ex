defmodule ExLibp2p.Rendezvous do
  @moduledoc """
  Rendezvous protocol for namespace-based peer discovery.

  Rendezvous allows peers to register under namespaces and discover
  other peers in the same namespace via a rendezvous server peer.

  Unlike mDNS (local network only) or DHT (global but slower), rendezvous
  provides fast, targeted discovery through a known rendezvous point.

  ## Usage

      # Register under a namespace at a rendezvous server
      :ok = ExLibp2p.Rendezvous.register(node, "my-service", rendezvous_peer, 3600)

      # Discover peers in a namespace
      :ok = ExLibp2p.Rendezvous.discover(node, "my-service", rendezvous_peer)

      # Results arrive as {:libp2p, :peer_discovered, %PeerDiscovered{}} events

      # Unregister
      :ok = ExLibp2p.Rendezvous.unregister(node, "my-service", rendezvous_peer)

  ## Configuration

      ExLibp2p.Node.start_link(
        enable_rendezvous_client: true,
        enable_rendezvous_server: true  # also serve as rendezvous point
      )

  """

  alias ExLibp2p.{Node, PeerId}

  @doc """
  Registers this node under a namespace at the given rendezvous server.

  The `rendezvous_peer` must be a connected peer running a rendezvous server.
  TTL is in seconds (how long the registration is valid).
  """
  @spec register(GenServer.server(), String.t(), PeerId.t(), non_neg_integer()) ::
          :ok | {:error, term()}
  def register(node, namespace, %PeerId{id: peer_str}, ttl_secs \\ 3600)
      when is_binary(namespace) do
    GenServer.call(node, {:rendezvous_register, namespace, ttl_secs, peer_str})
  end

  @doc """
  Discovers peers registered under a namespace at the given rendezvous server.

  Results arrive as `{:libp2p, :peer_discovered, %ExLibp2p.Node.Event.PeerDiscovered{}}` events.
  """
  @spec discover(GenServer.server(), String.t(), PeerId.t()) :: :ok | {:error, term()}
  def discover(node, namespace, %PeerId{id: peer_str}) when is_binary(namespace) do
    GenServer.call(node, {:rendezvous_discover, namespace, peer_str})
  end

  @doc "Unregisters this node from a namespace at the given rendezvous server."
  @spec unregister(GenServer.server(), String.t(), PeerId.t()) :: :ok | {:error, term()}
  def unregister(node, namespace, %PeerId{id: peer_str}) when is_binary(namespace) do
    GenServer.call(node, {:rendezvous_unregister, namespace, peer_str})
  end

  @doc "Registers the calling process to receive peer discovery events from rendezvous."
  @spec register_handler(GenServer.server(), pid()) :: :ok
  def register_handler(node, pid \\ self()) do
    Node.register_handler(node, :peer_discovered, pid)
  end
end
