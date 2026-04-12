defmodule ExLibp2p.Node.Config do
  @moduledoc """
  Configuration for a libp2p node.

  Provides sensible defaults for all settings. Pass overrides as a keyword list
  to `new/1`. The configuration is validated before being passed to the NIF layer.

  ## Examples

      iex> config = ExLibp2p.Node.Config.new()
      iex> config.enable_mdns
      true

      iex> config = ExLibp2p.Node.Config.new(enable_mdns: false, listen_addrs: ["/ip4/0.0.0.0/tcp/9000"])
      iex> config.enable_mdns
      false

  """

  @enforce_keys []
  # credo:disable-for-next-line
  defstruct keypair_bytes: nil,
            listen_addrs: ["/ip4/0.0.0.0/tcp/0", "/ip4/0.0.0.0/udp/0/quic-v1"],
            bootstrap_peers: [],
            # GossipSub
            gossipsub_topics: [],
            gossipsub_mesh_n: 6,
            gossipsub_mesh_n_low: 4,
            gossipsub_mesh_n_high: 12,
            gossipsub_gossip_lazy: 6,
            gossipsub_max_transmit_size: 65_536,
            gossipsub_heartbeat_interval_ms: 1000,
            gossipsub_peer_score: nil,
            gossipsub_thresholds: nil,
            # Protocol enables
            enable_mdns: true,
            enable_kademlia: true,
            enable_relay: false,
            enable_relay_server: false,
            enable_autonat: false,
            enable_upnp: false,
            enable_websocket: false,
            enable_rendezvous_client: false,
            enable_rendezvous_server: false,
            # Request-Response
            rpc_protocol_name: "/ex-libp2p/rpc/1.0.0",
            rpc_request_timeout_secs: 30,
            # Connection limits
            idle_connection_timeout_secs: 60,
            max_established_incoming: 256,
            max_established_outgoing: 256,
            max_pending_incoming: 128,
            max_pending_outgoing: 64,
            max_established_per_peer: 2,
            # Relay server config
            relay_max_reservations: 128,
            relay_max_circuits: 16,
            relay_max_circuit_duration_secs: 120,
            relay_max_circuit_bytes: 131_072

  @typedoc "Configuration for a libp2p node."
  @type t :: %__MODULE__{
          keypair_bytes: binary() | nil,
          listen_addrs: [String.t()],
          bootstrap_peers: [String.t()],
          gossipsub_topics: [String.t()],
          gossipsub_mesh_n: pos_integer(),
          gossipsub_mesh_n_low: pos_integer(),
          gossipsub_mesh_n_high: pos_integer(),
          gossipsub_gossip_lazy: pos_integer(),
          gossipsub_max_transmit_size: pos_integer(),
          gossipsub_heartbeat_interval_ms: pos_integer(),
          gossipsub_peer_score: ExLibp2p.Gossipsub.PeerScore.t() | nil,
          gossipsub_thresholds: ExLibp2p.Gossipsub.PeerScore.Thresholds.t() | nil,
          enable_mdns: boolean(),
          enable_kademlia: boolean(),
          enable_relay: boolean(),
          enable_relay_server: boolean(),
          enable_autonat: boolean(),
          enable_upnp: boolean(),
          enable_websocket: boolean(),
          enable_rendezvous_client: boolean(),
          enable_rendezvous_server: boolean(),
          rpc_protocol_name: String.t(),
          rpc_request_timeout_secs: pos_integer(),
          idle_connection_timeout_secs: pos_integer(),
          max_established_incoming: pos_integer(),
          max_established_outgoing: pos_integer(),
          max_pending_incoming: pos_integer(),
          max_pending_outgoing: pos_integer(),
          max_established_per_peer: pos_integer(),
          relay_max_reservations: pos_integer(),
          relay_max_circuits: pos_integer(),
          relay_max_circuit_duration_secs: pos_integer(),
          relay_max_circuit_bytes: pos_integer()
        }

  @known_keys [
    :keypair_bytes,
    :listen_addrs,
    :bootstrap_peers,
    :gossipsub_topics,
    :gossipsub_mesh_n,
    :gossipsub_mesh_n_low,
    :gossipsub_mesh_n_high,
    :gossipsub_gossip_lazy,
    :gossipsub_max_transmit_size,
    :gossipsub_heartbeat_interval_ms,
    :gossipsub_peer_score,
    :gossipsub_thresholds,
    :enable_mdns,
    :enable_kademlia,
    :enable_relay,
    :enable_relay_server,
    :enable_autonat,
    :enable_upnp,
    :enable_websocket,
    :enable_rendezvous_client,
    :enable_rendezvous_server,
    :rpc_protocol_name,
    :rpc_request_timeout_secs,
    :idle_connection_timeout_secs,
    :max_established_incoming,
    :max_established_outgoing,
    :max_pending_incoming,
    :max_pending_outgoing,
    :max_established_per_peer,
    :relay_max_reservations,
    :relay_max_circuits,
    :relay_max_circuit_duration_secs,
    :relay_max_circuit_bytes
  ]

  @doc """
  Creates a new config with default values.

  ## Examples

      iex> ExLibp2p.Node.Config.new().listen_addrs
      ["/ip4/0.0.0.0/tcp/0", "/ip4/0.0.0.0/udp/0/quic-v1"]

  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Creates a new config with the given overrides.

  Raises `ArgumentError` if unknown keys are provided.

  ## Examples

      iex> ExLibp2p.Node.Config.new(enable_mdns: false).enable_mdns
      false

  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    Keyword.validate!(opts, @known_keys)
    struct!(__MODULE__, opts)
  end

  @doc """
  Validates a config, returning `{:ok, config}` or `{:error, reason}`.

  ## Examples

      iex> ExLibp2p.Node.Config.validate(ExLibp2p.Node.Config.new())
      {:ok, %ExLibp2p.Node.Config{}}

  """
  @spec validate(t()) :: {:ok, t()} | {:error, atom()}
  def validate(%__MODULE__{listen_addrs: []}), do: {:error, :no_listen_addrs}

  def validate(%__MODULE__{idle_connection_timeout_secs: t}) when t <= 0,
    do: {:error, :invalid_timeout}

  def validate(%__MODULE__{} = config), do: {:ok, config}
end
