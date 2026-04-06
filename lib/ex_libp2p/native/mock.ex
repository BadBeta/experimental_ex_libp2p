defmodule ExLibp2p.Native.Mock do
  @moduledoc false
  @behaviour ExLibp2p.Native

  # Valid base58 peer ID (52 chars, all valid base58 characters)
  @mock_peer_id "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"
  @mock_peer_id_2 "12D3KooWRPmBBCBTuGh1cnUuFVr35GYnm4bRXYsSB94TXJLAg4mA"

  # --- Node lifecycle ---
  @impl true
  def start_node(_config), do: {:ok, make_ref()}

  @impl true
  def stop_node(_handle), do: :ok

  @impl true
  def register_event_handler(_handle, _pid), do: :ok

  @impl true
  def get_peer_id(_handle), do: @mock_peer_id

  @impl true
  def connected_peers(_handle), do: []

  @impl true
  def listening_addrs(_handle), do: ["/ip4/127.0.0.1/tcp/0"]

  @impl true
  def dial(_handle, _addr), do: :ok

  # --- GossipSub ---
  @impl true
  def publish(_handle, _topic, _data), do: :ok

  @impl true
  def subscribe(_handle, _topic), do: :ok

  @impl true
  def unsubscribe(_handle, _topic), do: :ok

  @impl true
  def gossipsub_mesh_peers(_handle, _topic), do: {:ok, [@mock_peer_id_2]}

  @impl true
  def gossipsub_all_peers(_handle), do: {:ok, [@mock_peer_id_2]}

  @impl true
  def gossipsub_peer_score(_handle, _peer_id), do: {:ok, 0.0}

  # --- DHT ---
  @impl true
  def dht_put(_handle, _key, _value), do: :ok

  @impl true
  def dht_get(_handle, _key), do: :ok

  @impl true
  def dht_find_peer(_handle, _peer_id), do: :ok

  @impl true
  def dht_provide(_handle, _key), do: :ok

  @impl true
  def dht_find_providers(_handle, _key), do: :ok

  @impl true
  def dht_bootstrap(_handle), do: :ok

  # --- Request-Response RPC ---
  @impl true
  def rpc_send_request(_handle, _peer_id, _data) do
    {:ok, "mock-request-#{System.unique_integer([:positive])}"}
  end

  @impl true
  def rpc_send_response(_handle, _channel_id, _data), do: :ok

  # --- Keypair ---
  @impl true
  def generate_keypair do
    id = System.unique_integer([:positive])
    # Generate a deterministic mock peer ID that passes base58 validation
    peer_id =
      "12D3KooW#{String.pad_leading("#{id}", 44, "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrs")}"

    # Encode the peer_id into the protobuf so from_protobuf can recover it
    {:ok, "mock-pubkey-#{id}", peer_id, "mock-proto:#{peer_id}"}
  end

  @impl true
  def keypair_from_protobuf("mock-proto:" <> peer_id) do
    {:ok, "mock-pubkey", peer_id}
  end

  def keypair_from_protobuf(_), do: {:error, :invalid_keypair}

  # --- Relay ---
  @impl true
  def listen_via_relay(_handle, _relay_addr), do: :ok

  # --- Metrics ---
  @impl true
  def bandwidth_stats(_handle), do: {:ok, 0, 0}

  # --- Rendezvous ---
  @impl true
  def rendezvous_register(_handle, _namespace, _ttl, _rendezvous_peer), do: :ok

  @impl true
  def rendezvous_discover(_handle, _namespace, _rendezvous_peer), do: :ok

  @impl true
  def rendezvous_unregister(_handle, _namespace, _rendezvous_peer), do: :ok
end
