defmodule ExLibp2p.Node.Config.Discovery do
  @moduledoc """
  Peer discovery: bootstrap list, mDNS, Kademlia DHT.

  `dht_state_path` is the file path the node uses to persist its
  Kademlia routing table across restarts. When set, the Node exports
  the routing table on `terminate/2` and re-imports it after `init/1`,
  letting a freshly-booted node skip rediscovery. Set to `nil` (default)
  to disable persistence — useful for ephemeral test nodes.
  """

  @enforce_keys []
  defstruct bootstrap_peers: [],
            enable_mdns: true,
            enable_kademlia: true,
            mdns_auto_dial: true,
            dht_state_path: nil

  @type t :: %__MODULE__{
          bootstrap_peers: [String.t()],
          enable_mdns: boolean(),
          enable_kademlia: boolean(),
          # When `true` (default), the node auto-dials every peer it learns
          # about via mDNS. Convenient for LAN auto-connect. Disable in
          # large-mesh stress tests or when the application drives dialing
          # explicitly — leaving auto-dial on with 50+ co-located nodes
          # creates a connection-attempt storm that prevents stable mesh
          # formation.
          mdns_auto_dial: boolean(),
          dht_state_path: String.t() | nil
        }
end
