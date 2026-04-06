defmodule ExLibp2p.Node.Event do
  @moduledoc """
  Event structs for libp2p node events.

  Events are received from the Rust NIF layer as tagged tuples and parsed into
  typed structs. Each event type has its own struct for pattern matching and
  type safety.

  ## Event Types

  - `ConnectionEstablished` — a new peer connection was established
  - `ConnectionClosed` — a peer connection was closed
  - `NewListenAddr` — the node started listening on a new address
  - `GossipsubMessage` — a GossipSub message was received
  - `PeerDiscovered` — a new peer was discovered (mDNS, DHT)
  - `DHTQueryResult` — a DHT query completed
  """

  alias ExLibp2p.PeerId

  # Struct definitions — these are separate modules that compile independently.
  # Defined inline for co-location but are fully independent modules.

  defmodule ConnectionEstablished do
    @moduledoc "Event emitted when a new peer connection is established."
    @enforce_keys [:peer_id, :num_established, :endpoint]
    defstruct [:peer_id, :num_established, :endpoint]

    @type t :: %__MODULE__{
            peer_id: ExLibp2p.PeerId.t(),
            num_established: non_neg_integer(),
            endpoint: :dialer | :listener
          }
  end

  defmodule ConnectionClosed do
    @moduledoc "Event emitted when a peer connection is closed."
    @enforce_keys [:peer_id, :num_established]
    defstruct [:peer_id, :num_established, :cause]

    @type t :: %__MODULE__{
            peer_id: ExLibp2p.PeerId.t(),
            num_established: non_neg_integer(),
            cause: atom() | nil
          }
  end

  defmodule NewListenAddr do
    @moduledoc "Event emitted when the node starts listening on a new address."
    @enforce_keys [:address]
    defstruct [:address, :listener_id]

    @type t :: %__MODULE__{
            address: String.t(),
            listener_id: String.t() | nil
          }
  end

  defmodule GossipsubMessage do
    @moduledoc "Event emitted when a GossipSub message is received."
    @enforce_keys [:topic, :data, :message_id]
    defstruct [:topic, :data, :source, :message_id]

    @type t :: %__MODULE__{
            topic: String.t(),
            data: binary(),
            source: ExLibp2p.PeerId.t() | nil,
            message_id: String.t()
          }
  end

  defmodule PeerDiscovered do
    @moduledoc "Event emitted when a new peer is discovered via mDNS or DHT."
    @enforce_keys [:peer_id, :addresses]
    defstruct [:peer_id, :addresses]

    @type t :: %__MODULE__{
            peer_id: ExLibp2p.PeerId.t(),
            addresses: [String.t()]
          }
  end

  defmodule DHTQueryResult do
    @moduledoc "Event emitted when a DHT query completes."
    @enforce_keys [:query_id, :result]
    defstruct [:query_id, :result]

    @type t :: %__MODULE__{
            query_id: String.t(),
            result: term()
          }
  end

  defmodule InboundRequest do
    @moduledoc "Event emitted when an inbound RPC request is received."
    @enforce_keys [:request_id, :channel_id, :peer_id, :data]
    defstruct [:request_id, :channel_id, :peer_id, :data]

    @type t :: %__MODULE__{
            request_id: String.t(),
            channel_id: String.t(),
            peer_id: ExLibp2p.PeerId.t(),
            data: binary()
          }
  end

  defmodule OutboundResponse do
    @moduledoc "Event emitted when a response to an outbound RPC request is received."
    @enforce_keys [:request_id, :peer_id, :data]
    defstruct [:request_id, :peer_id, :data]

    @type t :: %__MODULE__{
            request_id: String.t(),
            peer_id: ExLibp2p.PeerId.t(),
            data: binary()
          }
  end

  defmodule NatStatusChanged do
    @moduledoc "Event emitted when AutoNAT detects a change in NAT status."
    @enforce_keys [:status]
    defstruct [:status, :address]

    @type t :: %__MODULE__{
            status: :public | :private | :unknown,
            address: String.t() | nil
          }
  end

  defmodule RelayReservationAccepted do
    @moduledoc "Event emitted when a relay reservation is accepted."
    @enforce_keys [:relay_peer_id, :relay_addr]
    defstruct [:relay_peer_id, :relay_addr]

    @type t :: %__MODULE__{
            relay_peer_id: ExLibp2p.PeerId.t(),
            relay_addr: String.t()
          }
  end

  defmodule HolePunchOutcome do
    @moduledoc "Event emitted when a DCUtR hole punch attempt completes."
    @enforce_keys [:peer_id, :result]
    defstruct [:peer_id, :result]

    @type t :: %__MODULE__{
            peer_id: ExLibp2p.PeerId.t(),
            result: :success | {:failure, String.t()}
          }
  end

  defmodule ExternalAddrConfirmed do
    @moduledoc "Event emitted when an external address is confirmed reachable."
    @enforce_keys [:address]
    defstruct [:address]

    @type t :: %__MODULE__{address: String.t()}
  end

  defmodule DialFailure do
    @moduledoc "Event emitted when an outbound dial attempt fails."
    @enforce_keys [:error]
    defstruct [:peer_id, :error]

    @type t :: %__MODULE__{
            peer_id: ExLibp2p.PeerId.t() | nil,
            error: String.t()
          }
  end

  # Parsing functions — defined after struct modules so they're available.

  @doc """
  Parses a raw event tuple from the NIF layer into a typed event struct.

  Returns `{:ok, event}` or `{:error, :unknown_event}`.
  """
  @spec from_raw(tuple()) :: {:ok, struct()} | {:error, :unknown_event}
  def from_raw({:connection_established, peer_id_str, num_established, endpoint}) do
    {:ok,
     %ConnectionEstablished{
       peer_id: PeerId.new!(peer_id_str),
       num_established: num_established,
       endpoint: endpoint
     }}
  end

  def from_raw({:connection_closed, peer_id_str, num_established, cause}) do
    {:ok,
     %ConnectionClosed{
       peer_id: PeerId.new!(peer_id_str),
       num_established: num_established,
       cause: cause
     }}
  end

  def from_raw({:new_listen_addr, address, listener_id}) do
    {:ok,
     %NewListenAddr{
       address: address,
       listener_id: listener_id
     }}
  end

  def from_raw({:gossipsub_message, topic, data, nil, message_id}) do
    {:ok, %GossipsubMessage{topic: topic, data: data, source: nil, message_id: message_id}}
  end

  def from_raw({:gossipsub_message, topic, data, source_str, message_id}) do
    {:ok,
     %GossipsubMessage{
       topic: topic,
       data: data,
       source: PeerId.new!(source_str),
       message_id: message_id
     }}
  end

  def from_raw({:peer_discovered, peer_id_str, addresses}) do
    {:ok,
     %PeerDiscovered{
       peer_id: PeerId.new!(peer_id_str),
       addresses: addresses
     }}
  end

  def from_raw({:dht_query_result, query_id, result}) do
    {:ok, %DHTQueryResult{query_id: query_id, result: result}}
  end

  def from_raw({:inbound_request, request_id, channel_id, peer_id_str, data}) do
    {:ok,
     %InboundRequest{
       request_id: request_id,
       channel_id: channel_id,
       peer_id: PeerId.new!(peer_id_str),
       data: data
     }}
  end

  def from_raw({:outbound_response, request_id, peer_id_str, data}) do
    {:ok,
     %OutboundResponse{
       request_id: request_id,
       peer_id: PeerId.new!(peer_id_str),
       data: data
     }}
  end

  def from_raw({:nat_status_changed, status, address}) do
    {:ok, %NatStatusChanged{status: status, address: address}}
  end

  def from_raw({:relay_reservation_accepted, relay_peer_id_str, relay_addr}) do
    {:ok,
     %RelayReservationAccepted{
       relay_peer_id: PeerId.new!(relay_peer_id_str),
       relay_addr: relay_addr
     }}
  end

  def from_raw({:hole_punch_outcome, peer_id_str, result}) do
    {:ok,
     %HolePunchOutcome{
       peer_id: PeerId.new!(peer_id_str),
       result: result
     }}
  end

  def from_raw({:external_addr_confirmed, address}) do
    {:ok, %ExternalAddrConfirmed{address: address}}
  end

  def from_raw({:dial_failure, nil, error}) do
    {:ok, %DialFailure{peer_id: nil, error: error}}
  end

  def from_raw({:dial_failure, peer_id_str, error}) do
    {:ok, %DialFailure{peer_id: PeerId.new!(peer_id_str), error: error}}
  end

  def from_raw(_), do: {:error, :unknown_event}
end
