defmodule ExLibp2p.Native.Keypair do
  @moduledoc """
  Behaviour for cryptographic keypair operations.
  """

  @callback generate_keypair() :: {:ok, binary(), String.t(), binary()} | {:error, atom()}
  @callback keypair_from_protobuf(binary()) :: {:ok, binary(), String.t()} | {:error, atom()}
end
