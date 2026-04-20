defmodule ExLibp2p.Native.DHT do
  @moduledoc """
  Behaviour for Kademlia DHT operations.
  """

  @type handle :: reference()

  @callback dht_put(handle(), binary(), binary()) :: :ok | {:error, atom()}
  @callback dht_get(handle(), binary()) :: :ok | {:error, atom()}
  @callback dht_find_peer(handle(), String.t()) :: :ok | {:error, atom()}
  @callback dht_provide(handle(), binary()) :: :ok | {:error, atom()}
  @callback dht_find_providers(handle(), binary()) :: :ok | {:error, atom()}
  @callback dht_bootstrap(handle()) :: :ok | {:error, atom()}
end
