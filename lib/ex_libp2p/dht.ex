defmodule ExLibp2p.DHT do
  @moduledoc """
  Kademlia DHT operations for distributed storage and peer discovery.

  The DHT provides two core capabilities:
  - **Value records** — key-value storage distributed across the network
  - **Provider records** — content routing ("who has this content?")

  All operations are asynchronous. Results arrive as events to registered handlers.

  ## Usage

      :ok = ExLibp2p.DHT.register_handler(node)
      :ok = ExLibp2p.DHT.put_record(node, "my-key", "my-value")
      :ok = ExLibp2p.DHT.get_record(node, "my-key")

      # Results arrive as:
      # {:libp2p, :dht_query_result, %ExLibp2p.Node.Event.DHTQueryResult{}}

  """

  alias ExLibp2p.Node
  alias ExLibp2p.PeerId

  @doc "Stores a key-value record in the DHT."
  @spec put_record(GenServer.server(), binary(), binary()) :: :ok | {:error, term()}
  def put_record(node, key, value) when is_binary(key) and is_binary(value) do
    GenServer.call(node, {:dht_put, key, value})
  end

  @doc "Retrieves a record from the DHT. Results arrive as events."
  @spec get_record(GenServer.server(), binary()) :: :ok | {:error, term()}
  def get_record(node, key) when is_binary(key) do
    GenServer.call(node, {:dht_get, key})
  end

  @doc "Finds the addresses of a peer in the DHT. Results arrive as events."
  @spec find_peer(GenServer.server(), PeerId.t()) :: :ok | {:error, term()}
  def find_peer(node, %PeerId{id: peer_id_str}) do
    GenServer.call(node, {:dht_find_peer, peer_id_str})
  end

  @doc "Advertises this node as a provider for the given content key."
  @spec provide(GenServer.server(), binary()) :: :ok | {:error, term()}
  def provide(node, key) when is_binary(key) do
    GenServer.call(node, {:dht_provide, key})
  end

  @doc "Finds providers for a content key. Results arrive as events."
  @spec find_providers(GenServer.server(), binary()) :: :ok | {:error, term()}
  def find_providers(node, key) when is_binary(key) do
    GenServer.call(node, {:dht_find_providers, key})
  end

  @doc "Triggers a DHT bootstrap to populate the routing table."
  @spec bootstrap(GenServer.server()) :: :ok | {:error, term()}
  def bootstrap(node), do: GenServer.call(node, :dht_bootstrap)

  @doc """
  Registers the calling process to receive DHT query results.

  Results arrive as `{:libp2p, :dht_query_result, %ExLibp2p.Node.Event.DHTQueryResult{}}`.
  """
  @spec register_handler(GenServer.server(), pid()) :: :ok
  def register_handler(node, pid \\ self()),
    do: Node.register_handler(node, :dht_query_result, pid)
end
