defmodule ExLibp2p.Node.ConfigTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.Node.Config

  doctest ExLibp2p.Node.Config

  describe "new/0" do
    test "returns config with sensible defaults grouped into subgroups" do
      config = Config.new()

      assert config.network.listen_addrs == ["/ip4/0.0.0.0/tcp/0", "/ip4/0.0.0.0/udp/0/quic-v1"]
      assert config.discovery.bootstrap_peers == []
      assert config.gossipsub.topics == []
      assert config.discovery.enable_mdns == true
      assert config.discovery.enable_kademlia == true
      assert config.relay.enable == false
      assert config.network.idle_connection_timeout_secs == 60
      assert config.identity.keypair_bytes == nil
    end

    test "subgroups are reachable as struct fields" do
      config = Config.new()
      assert %Config.Identity{} = config.identity
      assert %Config.Network{} = config.network
      assert %Config.Discovery{} = config.discovery
      assert %Config.Gossipsub{} = config.gossipsub
      assert %Config.RequestResponse{} = config.request_response
      assert %Config.Relay{} = config.relay
      assert %Config.Rendezvous{} = config.rendezvous
    end
  end

  describe "new/1" do
    test "accepts flat keyword list overrides; routes them into the right subgroup" do
      config =
        Config.new(
          listen_addrs: ["/ip4/0.0.0.0/tcp/9000", "/ip4/0.0.0.0/udp/9000/quic-v1"],
          enable_mdns: false,
          idle_connection_timeout_secs: 120
        )

      assert config.network.listen_addrs == [
               "/ip4/0.0.0.0/tcp/9000",
               "/ip4/0.0.0.0/udp/9000/quic-v1"
             ]

      assert config.discovery.enable_mdns == false
      assert config.network.idle_connection_timeout_secs == 120
    end

    test "translates flat gossipsub_* opts into subgroup field names without the prefix" do
      config =
        Config.new(
          gossipsub_topics: ["alpha", "beta"],
          gossipsub_mesh_n: 8,
          gossipsub_heartbeat_interval_ms: 500
        )

      assert config.gossipsub.topics == ["alpha", "beta"]
      assert config.gossipsub.mesh_n == 8
      assert config.gossipsub.heartbeat_interval_ms == 500
    end

    test "translates rpc_* opts into request_response subgroup" do
      config = Config.new(rpc_protocol_name: "/custom/rpc/2.0", rpc_request_timeout_secs: 60)
      assert config.request_response.protocol_name == "/custom/rpc/2.0"
      assert config.request_response.request_timeout_secs == 60
    end

    test "translates enable_relay/enable_relay_server/relay_max_* into relay subgroup" do
      config =
        Config.new(
          enable_relay: true,
          enable_relay_server: true,
          relay_max_reservations: 64,
          relay_max_circuits: 8
        )

      assert config.relay.enable == true
      assert config.relay.enable_server == true
      assert config.relay.max_reservations == 64
      assert config.relay.max_circuits == 8
    end

    test "enable_autonat_server defaults to false; opt-in via Config.new/1" do
      assert Config.new().relay.enable_autonat_server == false
      assert Config.new(enable_autonat_server: true).relay.enable_autonat_server == true
    end

    test "dht_state_path defaults to nil; routes into discovery subgroup" do
      assert Config.new().discovery.dht_state_path == nil

      assert Config.new(dht_state_path: "/var/lib/exlibp2p/dht.bin").discovery.dht_state_path ==
               "/var/lib/exlibp2p/dht.bin"
    end

    test "translates enable_rendezvous_* into rendezvous subgroup" do
      config = Config.new(enable_rendezvous_client: true, enable_rendezvous_server: true)
      assert config.rendezvous.enable_client == true
      assert config.rendezvous.enable_server == true
    end

    test "rejects unknown keys" do
      assert_raise ArgumentError, ~r/unknown/, fn ->
        Config.new(unknown_key: true)
      end
    end
  end

  describe "validate/1" do
    test "valid config passes" do
      config = Config.new()
      assert {:ok, ^config} = Config.validate(config)
    end

    test "rejects empty listen_addrs" do
      config = Config.new(listen_addrs: [])
      assert {:error, :no_listen_addrs} = Config.validate(config)
    end

    test "rejects non-positive timeout" do
      config = Config.new(idle_connection_timeout_secs: 0)
      assert {:error, :invalid_timeout} = Config.validate(config)
    end

    test "rejects negative timeout" do
      config = Config.new(idle_connection_timeout_secs: -1)
      assert {:error, :invalid_timeout} = Config.validate(config)
    end

    test "returns {:error, :invalid_config} for non-Config input" do
      assert {:error, :invalid_config} = Config.validate(:not_a_config)
      assert {:error, :invalid_config} = Config.validate(%{})
      assert {:error, :invalid_config} = Config.validate(nil)
    end
  end

  describe "connection_limits (Network subgroup)" do
    test "returns default limits" do
      config = Config.new()

      assert config.network.max_established_incoming == 256
      assert config.network.max_established_outgoing == 256
      assert config.network.max_pending_incoming == 128
      assert config.network.max_pending_outgoing == 64
      assert config.network.max_established_per_peer == 2
    end

    test "accepts custom limits" do
      config = Config.new(max_established_incoming: 64, max_established_per_peer: 1)

      assert config.network.max_established_incoming == 64
      assert config.network.max_established_per_peer == 1
    end

    test "memory_max_percentage defaults to 0.9 (libp2p Rule 2 + memory_connection_limits)" do
      config = Config.new()
      assert config.network.memory_max_percentage == 0.9
    end

    test "accepts custom memory_max_percentage" do
      config = Config.new(memory_max_percentage: 0.75)
      assert config.network.memory_max_percentage == 0.75
    end
  end

  describe "to_nif_map/1" do
    test "flattens nested config to the flat string-keyed map the NIF expects" do
      m = Config.new() |> Config.to_nif_map()

      # Identity
      assert m["keypair_bytes"] == nil

      # Network
      assert m["listen_addrs"] == ["/ip4/0.0.0.0/tcp/0", "/ip4/0.0.0.0/udp/0/quic-v1"]
      assert m["idle_connection_timeout_secs"] == 60
      assert m["max_pending_incoming"] == 128
      assert m["memory_max_percentage"] == 0.9

      # Discovery
      assert m["bootstrap_peers"] == []
      assert m["enable_mdns"] == true

      # Gossipsub (re-prefixed back to flat)
      assert m["gossipsub_topics"] == []
      assert m["gossipsub_mesh_n"] == 6
      assert m["gossipsub_heartbeat_interval_ms"] == 1000

      # RequestResponse (re-prefixed back to rpc_)
      assert m["rpc_protocol_name"] == "/ex-libp2p/rpc/1.0.0"
      assert m["rpc_request_timeout_secs"] == 30

      # Relay (re-prefixed)
      assert m["enable_relay"] == false
      assert m["enable_relay_server"] == false
      assert m["enable_autonat_server"] == false
      assert m["relay_max_reservations"] == 128

      # Rendezvous (re-prefixed)
      assert m["enable_rendezvous_client"] == false
      assert m["enable_rendezvous_server"] == false
    end

    test "stringifies peer_score and thresholds nested structs" do
      peer_score = ExLibp2p.Gossipsub.PeerScore.new(behaviour_penalty_weight: -10.0)
      thresholds = ExLibp2p.Gossipsub.PeerScore.Thresholds.new(gossip_threshold: -100.0)

      m =
        Config.new(gossipsub_peer_score: peer_score, gossipsub_thresholds: thresholds)
        |> Config.to_nif_map()

      assert is_map(m["gossipsub_peer_score"])
      assert m["gossipsub_peer_score"]["behaviour_penalty_weight"] == -10.0
      assert is_map(m["gossipsub_thresholds"])
      assert m["gossipsub_thresholds"]["gossip_threshold"] == -100.0
    end

    test "preserves nil for absent peer_score / thresholds" do
      m = Config.new() |> Config.to_nif_map()
      assert m["gossipsub_peer_score"] == nil
      assert m["gossipsub_thresholds"] == nil
    end
  end
end
