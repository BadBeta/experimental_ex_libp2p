defmodule ExLibp2p.Relay do
  @moduledoc """
  Circuit Relay v2 for NAT traversal.

  When a node is behind NAT, it can use a publicly reachable relay node
  as an intermediary. The relay provides a reservation (listen address)
  and forwards traffic until a direct connection is established via
  DCUtR hole punching.

  ## Usage

      # Listen through a relay
      :ok = ExLibp2p.Relay.listen_via_relay(node, "/ip4/relay.example.com/tcp/4001/p2p/QmRelay...")

      # Register for relay events
      :ok = ExLibp2p.Relay.register_handler(node)

      # Events:
      # {:libp2p, :relay_reservation_accepted, %ExLibp2p.Node.Event.RelayReservationAccepted{}}
      # {:libp2p, :hole_punch_outcome, %ExLibp2p.Node.Event.HolePunchOutcome{}}

  ## Configuration

  Enable in node config:

      ExLibp2p.Node.start_link(
        enable_relay: true,       # enables relay client
        enable_relay_server: true  # also act as a relay for others
      )

  """

  alias ExLibp2p.Node

  import ExLibp2p.Call, only: [safe_call: 2]

  @doc """
  Listens through a relay node for inbound connections.

  The relay_addr should be a full multiaddr with the relay's peer ID.
  """
  @spec listen_via_relay(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def listen_via_relay(node, relay_addr) when is_binary(relay_addr) do
    safe_call(node, {:listen_via_relay, relay_addr})
  end

  @doc """
  Registers the calling process to receive relay and NAT traversal events.

  Events:
  - `{:libp2p, :nat_status_changed, %ExLibp2p.Node.Event.NatStatusChanged{}}`
  - `{:libp2p, :relay_reservation_accepted, %ExLibp2p.Node.Event.RelayReservationAccepted{}}`
  - `{:libp2p, :hole_punch_outcome, %ExLibp2p.Node.Event.HolePunchOutcome{}}`
  - `{:libp2p, :external_addr_confirmed, %ExLibp2p.Node.Event.ExternalAddrConfirmed{}}`
  """
  @spec register_handler(GenServer.server(), pid()) :: :ok
  def register_handler(node, pid \\ self()) do
    :ok = Node.register_handler(node, :nat_status_changed, pid)
    :ok = Node.register_handler(node, :relay_reservation_accepted, pid)
    :ok = Node.register_handler(node, :hole_punch_outcome, pid)
    Node.register_handler(node, :external_addr_confirmed, pid)
  end
end
