defmodule ExLibp2p.Multiaddr do
  @moduledoc """
  A libp2p multiaddress.

  Multiaddrs are self-describing network addresses used by libp2p.
  Format: `/protocol/value/protocol/value/...`

  ## Examples

      iex> {:ok, addr} = ExLibp2p.Multiaddr.new("/ip4/127.0.0.1/tcp/4001")
      iex> to_string(addr)
      "/ip4/127.0.0.1/tcp/4001"

      iex> ExLibp2p.Multiaddr.new("not a multiaddr")
      {:error, :invalid_multiaddr}

  """

  @enforce_keys [:address]
  defstruct [:address]

  @typedoc "A validated libp2p multiaddress."
  @type t :: %__MODULE__{address: String.t()}

  @known_protocols ~w(ip4 ip6 tcp udp quic quic-v1 dns dns4 dns6 dnsaddr ws wss p2p p2p-circuit webtransport webrtc-direct certhash)

  @doc """
  Creates a new `Multiaddr` from a string.

  Returns `{:ok, multiaddr}` if valid, `{:error, :invalid_multiaddr}` otherwise.
  Validation checks basic format — the Rust NIF performs full parsing.

  ## Examples

      iex> ExLibp2p.Multiaddr.new("/ip4/0.0.0.0/tcp/0")
      {:ok, %ExLibp2p.Multiaddr{address: "/ip4/0.0.0.0/tcp/0"}}

  """
  @spec new(term()) :: {:ok, t()} | {:error, :invalid_multiaddr}
  def new("/" <> _ = raw) do
    case raw |> String.split("/", trim: true) |> has_known_protocol?() do
      true -> {:ok, %__MODULE__{address: raw}}
      false -> {:error, :invalid_multiaddr}
    end
  end

  def new(_), do: {:error, :invalid_multiaddr}

  @doc """
  Creates a new `Multiaddr` from a string, raising on invalid input.

  ## Examples

      iex> ExLibp2p.Multiaddr.new!("/ip4/127.0.0.1/tcp/4001")
      %ExLibp2p.Multiaddr{address: "/ip4/127.0.0.1/tcp/4001"}

  """
  @spec new!(String.t()) :: t()
  def new!(raw) do
    case new(raw) do
      {:ok, addr} -> addr
      {:error, :invalid_multiaddr} -> raise ArgumentError, "invalid multiaddr: #{inspect(raw)}"
    end
  end

  @doc """
  Appends a `/p2p/<peer_id>` component to the multiaddr.

  ## Examples

      iex> addr = ExLibp2p.Multiaddr.new!("/ip4/127.0.0.1/tcp/4001")
      iex> peer = ExLibp2p.PeerId.new!("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")
      iex> result = ExLibp2p.Multiaddr.with_p2p(addr, peer)
      iex> to_string(result)
      "/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"

  """
  @spec with_p2p(t(), ExLibp2p.PeerId.t()) :: t()
  def with_p2p(%__MODULE__{address: address}, %ExLibp2p.PeerId{id: peer_id}) do
    %__MODULE__{address: address <> "/p2p/" <> peer_id}
  end

  defp has_known_protocol?([]), do: false

  defp has_known_protocol?(parts) do
    parts
    |> Enum.take_every(2)
    |> Enum.any?(&(&1 in @known_protocols))
  end

  defimpl String.Chars do
    def to_string(%ExLibp2p.Multiaddr{address: address}), do: address
  end

  defimpl Inspect do
    import Inspect.Algebra, only: [concat: 1]

    def inspect(%ExLibp2p.Multiaddr{address: address}, _opts) do
      concat(["#Multiaddr<", address, ">"])
    end
  end

  defimpl Jason.Encoder do
    alias Jason.Encode
    def encode(%ExLibp2p.Multiaddr{address: address}, opts), do: Encode.string(address, opts)
  end
end
