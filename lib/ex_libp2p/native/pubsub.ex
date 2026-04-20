defmodule ExLibp2p.Native.Pubsub do
  @moduledoc """
  Behaviour for GossipSub publish/subscribe operations.
  """

  @type handle :: reference()

  @callback publish(handle(), String.t(), binary()) :: :ok | {:error, atom()}
  @callback subscribe(handle(), String.t()) :: :ok | {:error, atom()}
  @callback unsubscribe(handle(), String.t()) :: :ok | {:error, atom()}
  @callback gossipsub_mesh_peers(handle(), String.t()) :: {:ok, [String.t()]} | {:error, atom()}
  @callback gossipsub_all_peers(handle()) :: {:ok, [String.t()]} | {:error, atom()}
  @callback gossipsub_peer_score(handle(), String.t()) :: {:ok, float()} | {:error, atom()}
end
