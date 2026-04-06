defmodule ExLibp2p.Native do
  @moduledoc """
  Behaviour defining the NIF interface for libp2p operations.

  Production uses `ExLibp2p.Native.Nif` (Rustler NIF).
  Tests use `ExLibp2p.Native.Mock`.

  Configure via:

      config :ex_libp2p, native_module: ExLibp2p.Native.Mock
  """

  @typedoc "Opaque handle to a native libp2p node."
  @type handle :: reference()

  # --- Node lifecycle ---
  @callback start_node(map()) :: {:ok, handle()} | {:error, term()}
  @callback stop_node(handle()) :: :ok
  @callback register_event_handler(handle(), pid()) :: :ok
  @callback get_peer_id(handle()) :: String.t()
  @callback connected_peers(handle()) :: [String.t()]
  @callback listening_addrs(handle()) :: [String.t()]
  @callback dial(handle(), String.t()) :: :ok | {:error, atom()}

  # --- GossipSub ---
  @callback publish(handle(), String.t(), binary()) :: :ok | {:error, atom()}
  @callback subscribe(handle(), String.t()) :: :ok | {:error, atom()}
  @callback unsubscribe(handle(), String.t()) :: :ok | {:error, atom()}
  @callback gossipsub_mesh_peers(handle(), String.t()) :: {:ok, [String.t()]} | {:error, atom()}
  @callback gossipsub_all_peers(handle()) :: {:ok, [String.t()]} | {:error, atom()}
  @callback gossipsub_peer_score(handle(), String.t()) :: {:ok, float()} | {:error, atom()}

  # --- DHT ---
  @callback dht_put(handle(), binary(), binary()) :: :ok | {:error, atom()}
  @callback dht_get(handle(), binary()) :: :ok | {:error, atom()}
  @callback dht_find_peer(handle(), String.t()) :: :ok | {:error, atom()}
  @callback dht_provide(handle(), binary()) :: :ok | {:error, atom()}
  @callback dht_find_providers(handle(), binary()) :: :ok | {:error, atom()}
  @callback dht_bootstrap(handle()) :: :ok | {:error, atom()}

  # --- Request-Response RPC ---
  @callback rpc_send_request(handle(), String.t(), binary()) :: {:ok, String.t()} | {:error, atom()}
  @callback rpc_send_response(handle(), String.t(), binary()) :: :ok | {:error, atom()}

  # --- Keypair ---
  @callback generate_keypair() :: {:ok, binary(), String.t(), binary()} | {:error, atom()}
  @callback keypair_from_protobuf(binary()) :: {:ok, binary(), String.t()} | {:error, atom()}

  # --- Relay ---
  @callback listen_via_relay(handle(), String.t()) :: :ok | {:error, atom()}

  # --- Metrics ---
  @callback bandwidth_stats(handle()) ::
              {:ok, non_neg_integer(), non_neg_integer()} | {:error, atom()}

  # --- Rendezvous ---
  @callback rendezvous_register(handle(), String.t(), non_neg_integer(), String.t()) ::
              :ok | {:error, atom()}
  @callback rendezvous_discover(handle(), String.t(), String.t()) :: :ok | {:error, atom()}
  @callback rendezvous_unregister(handle(), String.t(), String.t()) :: :ok | {:error, atom()}
end
