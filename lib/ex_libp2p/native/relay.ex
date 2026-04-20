defmodule ExLibp2p.Native.Relay do
  @moduledoc """
  Behaviour for circuit relay operations.
  """

  @type handle :: reference()

  @callback listen_via_relay(handle(), String.t()) :: :ok | {:error, atom()}
end
