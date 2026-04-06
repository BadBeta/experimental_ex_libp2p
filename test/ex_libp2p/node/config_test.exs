defmodule ExLibp2p.Node.ConfigTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.Node.Config

  doctest ExLibp2p.Node.Config

  describe "new/0" do
    test "returns config with sensible defaults" do
      config = Config.new()

      assert config.listen_addrs == ["/ip4/0.0.0.0/tcp/0"]
      assert config.bootstrap_peers == []
      assert config.gossipsub_topics == []
      assert config.enable_mdns == true
      assert config.enable_kademlia == true
      assert config.enable_relay == false
      assert config.idle_connection_timeout_secs == 60
      assert config.keypair_bytes == nil
    end
  end

  describe "new/1" do
    test "accepts keyword list overrides" do
      config =
        Config.new(
          listen_addrs: ["/ip4/0.0.0.0/tcp/9000", "/ip4/0.0.0.0/udp/9000/quic-v1"],
          enable_mdns: false,
          idle_connection_timeout_secs: 120
        )

      assert config.listen_addrs == ["/ip4/0.0.0.0/tcp/9000", "/ip4/0.0.0.0/udp/9000/quic-v1"]
      assert config.enable_mdns == false
      assert config.idle_connection_timeout_secs == 120
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
  end

  describe "connection_limits" do
    test "returns default limits" do
      config = Config.new()

      assert config.max_established_incoming == 256
      assert config.max_established_outgoing == 256
      assert config.max_pending_incoming == 128
      assert config.max_pending_outgoing == 64
      assert config.max_established_per_peer == 2
    end

    test "accepts custom limits" do
      config = Config.new(max_established_incoming: 64, max_established_per_peer: 1)

      assert config.max_established_incoming == 64
      assert config.max_established_per_peer == 1
    end
  end
end
