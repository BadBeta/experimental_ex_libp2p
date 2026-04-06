defmodule ExLibp2p.Gossipsub.PeerScore do
  @moduledoc """
  Peer scoring configuration for GossipSub v1.1.

  Peer scoring penalizes misbehaving peers and rewards useful ones.
  Without scoring, malicious peers can flood the network with impunity.

  ## Usage

      peer_score = ExLibp2p.Gossipsub.PeerScore.new(
        ip_colocation_factor_weight: -53.0,
        behaviour_penalty_weight: -15.92
      )

      thresholds = ExLibp2p.Gossipsub.PeerScore.Thresholds.new(
        gossip_threshold: -4000.0,
        publish_threshold: -8000.0
      )

      # Pass in node config:
      ExLibp2p.Node.start_link(
        gossipsub_peer_score: peer_score,
        gossipsub_thresholds: thresholds
      )

  """

  @enforce_keys []
  defstruct ip_colocation_factor_weight: -53.0,
            ip_colocation_factor_threshold: 3.0,
            behaviour_penalty_weight: -15.92,
            behaviour_penalty_decay: 0.986

  @type t :: %__MODULE__{
          ip_colocation_factor_weight: float(),
          ip_colocation_factor_threshold: float(),
          behaviour_penalty_weight: float(),
          behaviour_penalty_decay: float()
        }

  @doc "Creates peer score params with optional overrides."
  @spec new(keyword()) :: t()
  def new(opts \\ []), do: struct!(__MODULE__, opts)

  defmodule Thresholds do
    @moduledoc "Score thresholds controlling peer treatment at each score level."

    @enforce_keys []
    defstruct gossip_threshold: -4000.0,
              publish_threshold: -8000.0,
              graylist_threshold: -16_000.0,
              accept_px_threshold: 100.0,
              opportunistic_graft_threshold: 5.0

    @type t :: %__MODULE__{
            gossip_threshold: float(),
            publish_threshold: float(),
            graylist_threshold: float(),
            accept_px_threshold: float(),
            opportunistic_graft_threshold: float()
          }

    @doc "Creates thresholds with optional overrides."
    @spec new(keyword()) :: t()
    def new(opts \\ []), do: struct!(__MODULE__, opts)
  end

  defmodule TopicParams do
    @moduledoc "Per-topic scoring parameters."

    @enforce_keys []
    defstruct topic_weight: 1.0,
              time_in_mesh_weight: 0.0034,
              time_in_mesh_quantum_ms: 12,
              time_in_mesh_cap: 300.0,
              first_message_deliveries_weight: 1.0,
              first_message_deliveries_decay: 0.9916,
              first_message_deliveries_cap: 23.0,
              mesh_message_deliveries_weight: -0.717,
              mesh_message_deliveries_decay: 0.9972,
              mesh_message_deliveries_threshold: 0.11,
              mesh_message_deliveries_cap: 4.0,
              mesh_message_deliveries_activation_ms: 384_000,
              mesh_message_deliveries_window_ms: 2000,
              mesh_failure_penalty_weight: -0.717,
              mesh_failure_penalty_decay: 0.9972,
              invalid_message_deliveries_weight: -140.0,
              invalid_message_deliveries_decay: 0.997

    @type t :: %__MODULE__{
            topic_weight: float(),
            time_in_mesh_weight: float(),
            time_in_mesh_quantum_ms: non_neg_integer(),
            time_in_mesh_cap: float(),
            first_message_deliveries_weight: float(),
            first_message_deliveries_decay: float(),
            first_message_deliveries_cap: float(),
            mesh_message_deliveries_weight: float(),
            mesh_message_deliveries_decay: float(),
            mesh_message_deliveries_threshold: float(),
            mesh_message_deliveries_cap: float(),
            mesh_message_deliveries_activation_ms: non_neg_integer(),
            mesh_message_deliveries_window_ms: non_neg_integer(),
            mesh_failure_penalty_weight: float(),
            mesh_failure_penalty_decay: float(),
            invalid_message_deliveries_weight: float(),
            invalid_message_deliveries_decay: float()
          }

    @doc "Creates topic score params with optional overrides. Defaults are from Ethereum beacon chain."
    @spec new(keyword()) :: t()
    def new(opts \\ []), do: struct!(__MODULE__, opts)
  end
end
