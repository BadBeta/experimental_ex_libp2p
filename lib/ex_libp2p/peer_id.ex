defmodule ExLibp2p.PeerId do
  @moduledoc """
  A libp2p peer identifier.

  PeerIds are derived from a peer's public key and encoded as base58 strings.
  This module wraps the raw string in a struct for type safety, ensuring
  only validated peer IDs flow through the system.

  ## Examples

      iex> {:ok, peer_id} = ExLibp2p.PeerId.new("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")
      iex> to_string(peer_id)
      "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"

      iex> ExLibp2p.PeerId.new("")
      {:error, :invalid_peer_id}

  """

  @enforce_keys [:id]
  defstruct [:id]

  @typedoc "A validated libp2p peer identifier (base58-encoded)."
  @type t :: %__MODULE__{id: String.t()}

  @min_length 40
  @base58_chars ~c"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
  @base58_set MapSet.new(@base58_chars)

  @doc """
  Creates a new `PeerId` from a base58-encoded string.

  Returns `{:ok, peer_id}` if valid, `{:error, :invalid_peer_id}` otherwise.

  ## Examples

      iex> ExLibp2p.PeerId.new("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")
      {:ok, %ExLibp2p.PeerId{id: "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"}}

  """
  @spec new(term()) :: {:ok, t()} | {:error, :invalid_peer_id}
  def new(raw) when is_binary(raw) and byte_size(raw) >= @min_length do
    if base58?(raw), do: {:ok, %__MODULE__{id: raw}}, else: {:error, :invalid_peer_id}
  end

  def new(_), do: {:error, :invalid_peer_id}

  @doc """
  Creates a new `PeerId` from a base58-encoded string, raising on invalid input.

  ## Examples

      iex> ExLibp2p.PeerId.new!("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")
      %ExLibp2p.PeerId{id: "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"}

  """
  @spec new!(String.t()) :: t()
  def new!(raw) do
    case new(raw) do
      {:ok, peer_id} -> peer_id
      {:error, :invalid_peer_id} -> raise ArgumentError, "invalid peer ID: #{inspect(raw)}"
    end
  end

  defp base58?(<<char, rest::binary>>), do: char in @base58_set and base58?(rest)
  defp base58?(<<>>), do: true

  defimpl String.Chars do
    def to_string(%ExLibp2p.PeerId{id: id}), do: id
  end

  defimpl Inspect do
    import Inspect.Algebra, only: [concat: 1]

    def inspect(%ExLibp2p.PeerId{id: id}, _opts) do
      abbrev = String.slice(id, 0, 8) <> "..." <> String.slice(id, -4, 4)
      concat(["#PeerId<", abbrev, ">"])
    end
  end

  defimpl Jason.Encoder do
    alias Jason.Encode
    def encode(%ExLibp2p.PeerId{id: id}, opts), do: Encode.string(id, opts)
  end
end
