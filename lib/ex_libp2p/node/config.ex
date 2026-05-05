defmodule ExLibp2p.Node.Config do
  @moduledoc """
  Configuration for a libp2p node.

  Settings are organized into seven subgroups (`Identity`, `Network`, `Discovery`,
  `Gossipsub`, `RequestResponse`, `Relay`, `Rendezvous`) so callers and operators
  can reason about one concern at a time. The public `new/1` constructor still
  accepts a flat keyword list — overrides are routed into the matching subgroup.

  ## Examples

      iex> config = ExLibp2p.Node.Config.new()
      iex> config.discovery.enable_mdns
      true

      iex> config = ExLibp2p.Node.Config.new(enable_mdns: false, listen_addrs: ["/ip4/0.0.0.0/tcp/9000"])
      iex> config.discovery.enable_mdns
      false

  """

  alias __MODULE__.{Discovery, Gossipsub, Identity, Network, Relay, Rendezvous, RequestResponse}

  @enforce_keys []
  defstruct identity: %Identity{},
            network: %Network{},
            discovery: %Discovery{},
            gossipsub: %Gossipsub{},
            request_response: %RequestResponse{},
            relay: %Relay{},
            rendezvous: %Rendezvous{}

  @typedoc "Configuration for a libp2p node — seven subgroups."
  @type t :: %__MODULE__{
          identity: Identity.t(),
          network: Network.t(),
          discovery: Discovery.t(),
          gossipsub: Gossipsub.t(),
          request_response: RequestResponse.t(),
          relay: Relay.t(),
          rendezvous: Rendezvous.t()
        }

  # Flat-opt → subgroup-field translation tables. Drives both `new/1` (in)
  # and `to_nif_map/1` (out). Single source of truth for which flat key
  # belongs in which subgroup.
  @identity_keys [:keypair_bytes]
  @network_keys [
    :listen_addrs,
    :idle_connection_timeout_secs,
    :max_pending_incoming,
    :max_pending_outgoing,
    :max_established_incoming,
    :max_established_outgoing,
    :max_established_per_peer,
    :memory_max_percentage,
    :enable_websocket
  ]
  @discovery_keys [
    :bootstrap_peers,
    :enable_mdns,
    :enable_kademlia,
    :mdns_auto_dial,
    :dht_state_path
  ]
  @gossipsub_renames %{
    gossipsub_topics: :topics,
    gossipsub_mesh_n: :mesh_n,
    gossipsub_mesh_n_low: :mesh_n_low,
    gossipsub_mesh_n_high: :mesh_n_high,
    gossipsub_gossip_lazy: :gossip_lazy,
    gossipsub_max_transmit_size: :max_transmit_size,
    gossipsub_heartbeat_interval_ms: :heartbeat_interval_ms,
    gossipsub_peer_score: :peer_score,
    gossipsub_thresholds: :thresholds,
    gossipsub_peer_score_disabled: :peer_score_disabled
  }
  @request_response_renames %{
    rpc_protocol_name: :protocol_name,
    rpc_request_timeout_secs: :request_timeout_secs
  }
  @relay_renames %{
    enable_relay: :enable,
    enable_relay_server: :enable_server,
    enable_autonat: :enable_autonat,
    enable_autonat_server: :enable_autonat_server,
    enable_upnp: :enable_upnp,
    relay_max_reservations: :max_reservations,
    relay_max_circuits: :max_circuits,
    relay_max_circuit_duration_secs: :max_circuit_duration_secs,
    relay_max_circuit_bytes: :max_circuit_bytes
  }
  @rendezvous_renames %{
    enable_rendezvous_client: :enable_client,
    enable_rendezvous_server: :enable_server
  }

  @known_keys @identity_keys ++
                @network_keys ++
                @discovery_keys ++
                Map.keys(@gossipsub_renames) ++
                Map.keys(@request_response_renames) ++
                Map.keys(@relay_renames) ++
                Map.keys(@rendezvous_renames)

  @doc """
  Creates a new config with default values.

  ## Examples

      iex> ExLibp2p.Node.Config.new().network.listen_addrs
      ["/ip4/0.0.0.0/tcp/0", "/ip4/0.0.0.0/udp/0/quic-v1"]

  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Creates a new config with the given overrides.

  Accepts a flat keyword list — overrides are routed into the matching subgroup.
  Raises `ArgumentError` if unknown keys are provided.

  ## Examples

      iex> ExLibp2p.Node.Config.new(enable_mdns: false).discovery.enable_mdns
      false

  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    Keyword.validate!(opts, @known_keys)

    %__MODULE__{
      identity: %Identity{keypair_bytes: opts[:keypair_bytes]},
      network: struct(Network, Keyword.take(opts, @network_keys)),
      discovery: struct(Discovery, Keyword.take(opts, @discovery_keys)),
      gossipsub: struct(Gossipsub, take_with_renames(opts, @gossipsub_renames)),
      request_response: struct(RequestResponse, take_with_renames(opts, @request_response_renames)),
      relay: struct(Relay, take_with_renames(opts, @relay_renames)),
      rendezvous: struct(Rendezvous, take_with_renames(opts, @rendezvous_renames))
    }
  end

  @doc """
  Validates a config, returning `{:ok, config}` or `{:error, reason}`.

  ## Examples

      iex> ExLibp2p.Node.Config.validate(ExLibp2p.Node.Config.new())
      {:ok, %ExLibp2p.Node.Config{}}

  """
  @spec validate(t()) :: {:ok, t()} | {:error, atom()}
  def validate(%__MODULE__{network: %Network{listen_addrs: []}}), do: {:error, :no_listen_addrs}

  def validate(%__MODULE__{network: %Network{idle_connection_timeout_secs: t}}) when t <= 0,
    do: {:error, :invalid_timeout}

  def validate(%__MODULE__{} = config), do: {:ok, config}

  def validate(_), do: {:error, :invalid_config}

  @doc """
  Flattens the nested config into the string-keyed map the NIF expects.

  The Rust `crate::config::NodeConfig::from_map` reads a flat `HashMap<String,
  Term>` — this function is the single point that translates from the
  Elixir-side nested struct shape to the Rust-side flat shape. `peer_score` and
  `thresholds` stay nested as string-keyed maps because the Rust side decodes
  them as inner HashMaps.
  """
  @spec to_nif_map(t()) :: %{String.t() => term()}
  def to_nif_map(%__MODULE__{} = config) do
    %{
      # Identity
      "keypair_bytes" => config.identity.keypair_bytes,

      # Network
      "listen_addrs" => config.network.listen_addrs,
      "idle_connection_timeout_secs" => config.network.idle_connection_timeout_secs,
      "max_pending_incoming" => config.network.max_pending_incoming,
      "max_pending_outgoing" => config.network.max_pending_outgoing,
      "max_established_incoming" => config.network.max_established_incoming,
      "max_established_outgoing" => config.network.max_established_outgoing,
      "max_established_per_peer" => config.network.max_established_per_peer,
      "memory_max_percentage" => config.network.memory_max_percentage,
      "enable_websocket" => config.network.enable_websocket,

      # Discovery
      "bootstrap_peers" => config.discovery.bootstrap_peers,
      "enable_mdns" => config.discovery.enable_mdns,
      "enable_kademlia" => config.discovery.enable_kademlia,
      "mdns_auto_dial" => config.discovery.mdns_auto_dial,

      # Gossipsub (renamed back to flat NIF keys)
      "gossipsub_topics" => config.gossipsub.topics,
      "gossipsub_mesh_n" => config.gossipsub.mesh_n,
      "gossipsub_mesh_n_low" => config.gossipsub.mesh_n_low,
      "gossipsub_mesh_n_high" => config.gossipsub.mesh_n_high,
      "gossipsub_gossip_lazy" => config.gossipsub.gossip_lazy,
      "gossipsub_max_transmit_size" => config.gossipsub.max_transmit_size,
      "gossipsub_heartbeat_interval_ms" => config.gossipsub.heartbeat_interval_ms,
      "gossipsub_peer_score" => stringify_struct(config.gossipsub.peer_score),
      "gossipsub_thresholds" => stringify_struct(config.gossipsub.thresholds),
      "peer_score_disabled" => config.gossipsub.peer_score_disabled,

      # Request-Response
      "rpc_protocol_name" => config.request_response.protocol_name,
      "rpc_request_timeout_secs" => config.request_response.request_timeout_secs,

      # Relay
      "enable_relay" => config.relay.enable,
      "enable_relay_server" => config.relay.enable_server,
      "enable_autonat" => config.relay.enable_autonat,
      "enable_autonat_server" => config.relay.enable_autonat_server,
      "enable_upnp" => config.relay.enable_upnp,
      "relay_max_reservations" => config.relay.max_reservations,
      "relay_max_circuits" => config.relay.max_circuits,
      "relay_max_circuit_duration_secs" => config.relay.max_circuit_duration_secs,
      "relay_max_circuit_bytes" => config.relay.max_circuit_bytes,

      # Rendezvous
      "enable_rendezvous_client" => config.rendezvous.enable_client,
      "enable_rendezvous_server" => config.rendezvous.enable_server
    }
  end

  # --- Private ---

  defp take_with_renames(opts, rename_map) do
    Enum.reduce(rename_map, [], fn {flat_key, field}, acc ->
      case Keyword.fetch(opts, flat_key) do
        {:ok, value} -> [{field, value} | acc]
        :error -> acc
      end
    end)
  end

  defp stringify_struct(nil), do: nil

  defp stringify_struct(%{__struct__: _} = s) do
    s |> Map.from_struct() |> Map.new(fn {k, v} -> {to_string(k), v} end)
  end
end
