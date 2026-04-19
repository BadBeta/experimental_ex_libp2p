defmodule ExLibp2p.Discovery do
  @moduledoc """
  Peer discovery via mDNS and bootstrap peers.

  mDNS discovers peers on the local network automatically when `enable_mdns: true`
  in the node config. Bootstrap peers provide initial DHT connectivity for
  wide-area networks.

  ## Usage

      :ok = ExLibp2p.Discovery.register_handler(node)
      :ok = ExLibp2p.Discovery.bootstrap(node, [
        "/ip4/104.131.131.82/tcp/4001/p2p/QmaCpDMGvV2BGHeYER..."
      ])

      # Discovered peers arrive as:
      # {:libp2p, :peer_discovered, %ExLibp2p.Node.Event.PeerDiscovered{}}

  """

  alias ExLibp2p.Node

  import ExLibp2p.Call, only: [safe_call: 2]

  @doc """
  Registers the calling process to receive peer discovery events.

  Events arrive as `{:libp2p, :peer_discovered, %ExLibp2p.Node.Event.PeerDiscovered{}}`.
  """
  @spec register_handler(GenServer.server(), pid()) :: :ok
  def register_handler(node, pid \\ self()),
    do: Node.register_handler(node, :peer_discovered, pid)

  @doc """
  Dials a list of bootstrap peers and triggers DHT bootstrap.

  Each peer address should be a multiaddr string with a `/p2p/<peer_id>` component.
  Returns `{:ok, results}` with per-peer dial results, or `:ok` for empty list.
  """
  @spec bootstrap(GenServer.server(), [String.t()]) ::
          :ok | {:ok, [dial_result]} | {:error, term()}
        when dial_result: :ok | {:error, term()}
  def bootstrap(_node, []), do: :ok

  def bootstrap(node, peer_addrs) when is_list(peer_addrs) do
    dial_results = Enum.map(peer_addrs, &Node.dial(node, &1))

    with :ok <- safe_call(node, :dht_bootstrap) do
      {:ok, dial_results}
    end
  end
end
