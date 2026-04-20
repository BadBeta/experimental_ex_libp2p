defmodule ExLibp2p.Native.Rendezvous do
  @moduledoc """
  Behaviour for rendezvous peer discovery operations.
  """

  @type handle :: reference()

  @callback rendezvous_register(handle(), String.t(), non_neg_integer(), String.t()) ::
              :ok | {:error, atom()}
  @callback rendezvous_discover(handle(), String.t(), String.t()) :: :ok | {:error, atom()}
  @callback rendezvous_unregister(handle(), String.t(), String.t()) :: :ok | {:error, atom()}
end
