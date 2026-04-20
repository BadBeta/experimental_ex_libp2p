defmodule ExLibp2p.Native do
  @moduledoc """
  Aggregate behaviour defining the full NIF interface for libp2p operations.

  Composed of focused sub-behaviours:

    - `ExLibp2p.Native.Core` — node lifecycle, peer identity, connectivity
    - `ExLibp2p.Native.Pubsub` — GossipSub publish/subscribe
    - `ExLibp2p.Native.DHT` — Kademlia DHT operations
    - `ExLibp2p.Native.RPC` — request-response protocol
    - `ExLibp2p.Native.Keypair` — cryptographic keypair operations
    - `ExLibp2p.Native.Relay` — circuit relay
    - `ExLibp2p.Native.Metrics` — bandwidth statistics
    - `ExLibp2p.Native.Rendezvous` — rendezvous peer discovery

  Production uses `ExLibp2p.Native.Nif` (Rustler NIF).
  Tests use `ExLibp2p.Native.Mock`.

  Configure via:

      config :ex_libp2p, native_module: ExLibp2p.Native.Mock

  Modules that only need a subset of NIF functions can depend on the
  specific sub-behaviour instead of the full aggregate.
  """

  @typedoc "Opaque handle to a native libp2p node."
  @type handle :: reference()

  # Re-export all sub-behaviour callbacks so existing
  # `@behaviour ExLibp2p.Native` declarations continue to work.

  # --- Core (7 callbacks) ---
  @callback start_node(map()) :: {:ok, handle()} | {:error, term()}
  @callback stop_node(handle()) :: :ok
  @callback register_event_handler(handle(), pid()) :: :ok
  @callback get_peer_id(handle()) :: String.t()
  @callback connected_peers(handle()) :: [String.t()]
  @callback listening_addrs(handle()) :: [String.t()]
  @callback dial(handle(), String.t()) :: :ok | {:error, atom()}

  # --- Pubsub (6 callbacks) ---
  @callback publish(handle(), String.t(), binary()) :: :ok | {:error, atom()}
  @callback subscribe(handle(), String.t()) :: :ok | {:error, atom()}
  @callback unsubscribe(handle(), String.t()) :: :ok | {:error, atom()}
  @callback gossipsub_mesh_peers(handle(), String.t()) :: {:ok, [String.t()]} | {:error, atom()}
  @callback gossipsub_all_peers(handle()) :: {:ok, [String.t()]} | {:error, atom()}
  @callback gossipsub_peer_score(handle(), String.t()) :: {:ok, float()} | {:error, atom()}

  # --- DHT (6 callbacks) ---
  @callback dht_put(handle(), binary(), binary()) :: :ok | {:error, atom()}
  @callback dht_get(handle(), binary()) :: :ok | {:error, atom()}
  @callback dht_find_peer(handle(), String.t()) :: :ok | {:error, atom()}
  @callback dht_provide(handle(), binary()) :: :ok | {:error, atom()}
  @callback dht_find_providers(handle(), binary()) :: :ok | {:error, atom()}
  @callback dht_bootstrap(handle()) :: :ok | {:error, atom()}

  # --- RPC (2 callbacks) ---
  @callback rpc_send_request(handle(), String.t(), binary()) ::
              {:ok, String.t()} | {:error, atom()}
  @callback rpc_send_response(handle(), String.t(), binary()) :: :ok | {:error, atom()}

  # --- Keypair (2 callbacks) ---
  @callback generate_keypair() :: {:ok, binary(), String.t(), binary()} | {:error, atom()}
  @callback keypair_from_protobuf(binary()) :: {:ok, binary(), String.t()} | {:error, atom()}

  # --- Relay (1 callback) ---
  @callback listen_via_relay(handle(), String.t()) :: :ok | {:error, atom()}

  # --- Metrics (1 callback) ---
  @callback bandwidth_stats(handle()) ::
              {:ok, non_neg_integer(), non_neg_integer()} | {:error, atom()}

  # --- Rendezvous (3 callbacks) ---
  @callback rendezvous_register(handle(), String.t(), non_neg_integer(), String.t()) ::
              :ok | {:error, atom()}
  @callback rendezvous_discover(handle(), String.t(), String.t()) :: :ok | {:error, atom()}
  @callback rendezvous_unregister(handle(), String.t(), String.t()) :: :ok | {:error, atom()}
end
