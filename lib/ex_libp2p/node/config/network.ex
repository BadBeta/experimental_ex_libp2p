defmodule ExLibp2p.Node.Config.Network do
  @moduledoc """
  Transport, connection-limit, and per-process resource config.

  `idle_connection_timeout_secs` (libp2p Rule 5), the five connection limits
  (libp2p Rule 2), and `memory_max_percentage` cap the node's footprint and
  are non-negotiable for production deployments.
  """

  @enforce_keys []
  defstruct listen_addrs: ["/ip4/0.0.0.0/tcp/0", "/ip4/0.0.0.0/udp/0/quic-v1"],
            idle_connection_timeout_secs: 60,
            max_pending_incoming: 128,
            max_pending_outgoing: 64,
            max_established_incoming: 256,
            max_established_outgoing: 256,
            max_established_per_peer: 2,
            memory_max_percentage: 0.9,
            enable_websocket: false

  @type t :: %__MODULE__{
          listen_addrs: [String.t()],
          idle_connection_timeout_secs: pos_integer(),
          max_pending_incoming: pos_integer(),
          max_pending_outgoing: pos_integer(),
          max_established_incoming: pos_integer(),
          max_established_outgoing: pos_integer(),
          max_established_per_peer: pos_integer(),
          memory_max_percentage: float(),
          enable_websocket: boolean()
        }
end
