defmodule ExLibp2p.Native.DHT do
  @moduledoc """
  Behaviour for Kademlia DHT operations.
  """

  @type handle :: reference()

  @callback dht_put(handle(), binary(), binary()) :: :ok | {:error, term()}
  @callback dht_get(handle(), binary()) :: :ok | {:error, term()}
  @callback dht_find_peer(handle(), String.t()) :: :ok | {:error, term()}
  @callback dht_provide(handle(), binary()) :: :ok | {:error, term()}
  @callback dht_find_providers(handle(), binary()) :: :ok | {:error, term()}
  @callback dht_bootstrap(handle()) :: :ok | {:error, term()}

  @doc """
  Exports the current Kademlia routing table as an opaque binary blob.
  Format is implementation-defined and consumed only by `kad_import_routing_table/2`.
  Returns `{:error, {:dht_not_enabled, _}}` when Kademlia is disabled.
  """
  @callback kad_export_routing_table(handle()) :: {:ok, binary()} | {:error, term()}

  @doc """
  Imports a routing-table blob produced by `kad_export_routing_table/1`.
  Returns `{:ok, count}` where `count` is the number of (peer, addr)
  pairs added to Kademlia's routing table. Returns
  `{:error, {:input_too_large, _}}` if the blob exceeds the size cap, and
  `{:error, {:dht_not_enabled, _}}` when Kademlia is disabled.
  """
  @callback kad_import_routing_table(handle(), binary()) ::
              {:ok, non_neg_integer()} | {:error, term()}
end
