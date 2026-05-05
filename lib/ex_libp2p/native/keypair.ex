defmodule ExLibp2p.Native.Keypair do
  @moduledoc """
  Behaviour for cryptographic keypair operations.
  """

  @callback generate_keypair() :: {:ok, binary(), String.t(), binary()} | {:error, term()}
  @callback keypair_from_protobuf(binary()) :: {:ok, binary(), String.t()} | {:error, term()}
end
