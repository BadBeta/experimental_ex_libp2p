defmodule ExLibp2p.Node.Config.Gossipsub do
  @moduledoc """
  GossipSub mesh and scoring config. Defaults match libp2p v1.0 mesh
  parameters (D=6, D_low=4, D_high=12, D_lazy=6).

  ## Peer scoring is default-on

  Peer scoring is applied automatically with Ethereum beacon chain
  reference defaults (sourced from the `policy` module on the Rust side).
  Set `peer_score_disabled: true` to skip scoring entirely; provide
  custom `peer_score` / `thresholds` structs to override the defaults
  per-field.
  """

  @enforce_keys []
  defstruct topics: [],
            mesh_n: 6,
            mesh_n_low: 4,
            mesh_n_high: 12,
            gossip_lazy: 6,
            max_transmit_size: 65_536,
            heartbeat_interval_ms: 1000,
            peer_score: nil,
            thresholds: nil,
            peer_score_disabled: false

  @type t :: %__MODULE__{
          topics: [String.t()],
          mesh_n: pos_integer(),
          mesh_n_low: pos_integer(),
          mesh_n_high: pos_integer(),
          gossip_lazy: pos_integer(),
          max_transmit_size: pos_integer(),
          heartbeat_interval_ms: pos_integer(),
          peer_score: ExLibp2p.Gossipsub.PeerScore.t() | nil,
          thresholds: ExLibp2p.Gossipsub.PeerScore.Thresholds.t() | nil,
          peer_score_disabled: boolean()
        }
end
