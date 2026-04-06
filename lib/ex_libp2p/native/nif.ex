defmodule ExLibp2p.Native.Nif do
  @moduledoc false
  @behaviour ExLibp2p.Native

  version = Mix.Project.config()[:version]

  use RustlerPrecompiled,
    otp_app: :ex_libp2p,
    crate: "ex_libp2p_nif",
    base_url: "https://github.com/badbeta/ex_libp2p/releases/download/v#{version}",
    force_build: System.get_env("EX_LIBP2P_BUILD") in ["1", "true"],
    targets:
      Enum.uniq(
        ["aarch64-apple-darwin", "x86_64-apple-darwin"] ++
          RustlerPrecompiled.Config.default_targets()
      ),
    version: version

  @impl true
  @spec start_node(map()) :: {:ok, reference()} | {:error, term()}
  def start_node(_config), do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec stop_node(reference()) :: :ok
  def stop_node(_handle), do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec register_event_handler(reference(), pid()) :: :ok
  def register_event_handler(_handle, _pid), do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec get_peer_id(reference()) :: String.t()
  def get_peer_id(_handle), do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec connected_peers(reference()) :: [String.t()]
  def connected_peers(_handle), do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec listening_addrs(reference()) :: [String.t()]
  def listening_addrs(_handle), do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec dial(reference(), String.t()) :: :ok | {:error, atom()}
  def dial(_handle, _addr), do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec publish(reference(), String.t(), binary()) :: :ok | {:error, atom()}
  def publish(_handle, _topic, _data), do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec subscribe(reference(), String.t()) :: :ok | {:error, atom()}
  def subscribe(_handle, _topic), do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec unsubscribe(reference(), String.t()) :: :ok | {:error, atom()}
  def unsubscribe(_handle, _topic), do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec dht_put(reference(), binary(), binary()) :: :ok | {:error, atom()}
  def dht_put(_handle, _key, _value), do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec dht_get(reference(), binary()) :: :ok | {:error, atom()}
  def dht_get(_handle, _key), do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec dht_find_peer(reference(), String.t()) :: :ok | {:error, atom()}
  def dht_find_peer(_handle, _peer_id), do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec dht_provide(reference(), binary()) :: :ok | {:error, atom()}
  def dht_provide(_handle, _key), do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec dht_find_providers(reference(), binary()) :: :ok | {:error, atom()}
  def dht_find_providers(_handle, _key), do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec dht_bootstrap(reference()) :: :ok | {:error, atom()}
  def dht_bootstrap(_handle), do: :erlang.nif_error(:nif_not_loaded)

  # --- Request-Response RPC ---
  @impl true
  @spec rpc_send_request(reference(), String.t(), binary()) :: {:ok, String.t()} | {:error, atom()}
  def rpc_send_request(_handle, _peer_id, _data), do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec rpc_send_response(reference(), String.t(), binary()) :: :ok | {:error, atom()}
  def rpc_send_response(_handle, _channel_id, _data), do: :erlang.nif_error(:nif_not_loaded)

  # --- Keypair ---
  @impl true
  @spec generate_keypair() :: {:ok, binary(), String.t(), binary()} | {:error, atom()}
  def generate_keypair, do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec keypair_from_protobuf(binary()) :: {:ok, binary(), String.t()} | {:error, atom()}
  def keypair_from_protobuf(_bytes), do: :erlang.nif_error(:nif_not_loaded)

  # --- GossipSub advanced ---
  @impl true
  @spec gossipsub_mesh_peers(reference(), String.t()) :: {:ok, [String.t()]} | {:error, atom()}
  def gossipsub_mesh_peers(_handle, _topic), do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec gossipsub_all_peers(reference()) :: {:ok, [String.t()]} | {:error, atom()}
  def gossipsub_all_peers(_handle), do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec gossipsub_peer_score(reference(), String.t()) :: {:ok, float()} | {:error, atom()}
  def gossipsub_peer_score(_handle, _peer_id), do: :erlang.nif_error(:nif_not_loaded)

  # --- Relay ---
  @impl true
  @spec listen_via_relay(reference(), String.t()) :: :ok | {:error, atom()}
  def listen_via_relay(_handle, _relay_addr), do: :erlang.nif_error(:nif_not_loaded)

  # --- Metrics ---
  @impl true
  @spec bandwidth_stats(reference()) ::
          {:ok, non_neg_integer(), non_neg_integer()} | {:error, atom()}
  def bandwidth_stats(_handle), do: :erlang.nif_error(:nif_not_loaded)

  # --- Rendezvous ---
  @impl true
  @spec rendezvous_register(reference(), String.t(), non_neg_integer(), String.t()) ::
          :ok | {:error, atom()}
  def rendezvous_register(_handle, _namespace, _ttl, _rendezvous_peer),
    do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec rendezvous_discover(reference(), String.t(), String.t()) :: :ok | {:error, atom()}
  def rendezvous_discover(_handle, _namespace, _rendezvous_peer),
    do: :erlang.nif_error(:nif_not_loaded)

  @impl true
  @spec rendezvous_unregister(reference(), String.t(), String.t()) :: :ok | {:error, atom()}
  def rendezvous_unregister(_handle, _namespace, _rendezvous_peer),
    do: :erlang.nif_error(:nif_not_loaded)
end
