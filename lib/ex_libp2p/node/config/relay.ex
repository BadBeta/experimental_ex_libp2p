defmodule ExLibp2p.Node.Config.Relay do
  @moduledoc """
  NAT traversal stack: relay v2 client/server, AutoNAT, UPnP. DCUtR is
  activated implicitly when `enable: true` (matches Rust-side composition).
  Relay-server limits cap reservations and circuit duration/bytes.

  AutoNAT split — `enable_autonat` toggles the v1 AutoNAT client (the
  status-changed event consumer that drives `:nat_status_changed`).
  `enable_autonat_server` toggles the AutoNAT v2 dial-back server, which
  is amplification-resistant and probes via fresh ports — turn this on
  for publicly reachable nodes (relay / bootstrap nodes) so they can
  serve v2 clients.
  """

  @enforce_keys []
  defstruct enable: false,
            enable_server: false,
            enable_autonat: false,
            enable_autonat_server: false,
            enable_upnp: false,
            max_reservations: 128,
            max_circuits: 16,
            max_circuit_duration_secs: 120,
            max_circuit_bytes: 131_072

  @type t :: %__MODULE__{
          enable: boolean(),
          enable_server: boolean(),
          enable_autonat: boolean(),
          enable_autonat_server: boolean(),
          enable_upnp: boolean(),
          max_reservations: pos_integer(),
          max_circuits: pos_integer(),
          max_circuit_duration_secs: pos_integer(),
          max_circuit_bytes: pos_integer()
        }
end
