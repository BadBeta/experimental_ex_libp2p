defmodule ExLibp2p.Native.RPC do
  @moduledoc """
  Behaviour for request-response RPC operations.
  """

  @type handle :: reference()

  @callback rpc_send_request(handle(), String.t(), binary()) ::
              {:ok, String.t()} | {:error, atom()}
  @callback rpc_send_response(handle(), String.t(), binary()) :: :ok | {:error, atom()}
end
