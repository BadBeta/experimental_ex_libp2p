defmodule ExLibp2p.Gossipsub.PeerScoreDefaultTest do
  @moduledoc """
  Verifies R2: GossipSub peer scoring is default-on.

  Before R2, a node started without explicit `gossipsub_peer_score:` opts
  would skip `with_peer_score()` entirely — calling
  `Gossipsub.peer_score(node, peer)` returned `{:ok, 0.0}` because
  libp2p's `gossipsub.peer_score()` returns `None` for unscored peers,
  which the NIF used to map to `0.0`. The behavioural difference between
  scored-vs-unscored is now: scored returns a real number; unscored
  STILL returns 0.0 for unknown peers, but the underlying scoring graph
  is being built.

  Direct verification that scoring is wired requires connecting two real
  nodes and observing score-driven behaviour — too heavy for unit tests.
  This test instead verifies that the opt-out flag actually disables
  scoring (by exercising the config path) and that the default config
  carries `peer_score_disabled = false`.
  """
  use ExUnit.Case, async: true

  alias ExLibp2p.Node.Config

  describe "Config.Gossipsub default-on scoring" do
    test "default config has peer_score_disabled = false" do
      config = Config.new()
      assert config.gossipsub.peer_score_disabled == false
    end

    test "to_nif_map exports peer_score_disabled key" do
      m = Config.new() |> Config.to_nif_map()
      assert m["peer_score_disabled"] == false
    end

    test "opt-out flag flows through to_nif_map" do
      m =
        Config.new(gossipsub_peer_score_disabled: true)
        |> Config.to_nif_map()

      assert m["peer_score_disabled"] == true
    end

    test "user-supplied peer_score override still propagates" do
      ps =
        ExLibp2p.Gossipsub.PeerScore.new(
          ip_colocation_factor_weight: -100.0,
          behaviour_penalty_weight: -20.0
        )

      m =
        Config.new(gossipsub_peer_score: ps)
        |> Config.to_nif_map()

      assert is_map(m["gossipsub_peer_score"])
      assert m["gossipsub_peer_score"]["ip_colocation_factor_weight"] == -100.0
      # peer_score_disabled stays at the default — user-supplied params
      # don't imply opt-out.
      assert m["peer_score_disabled"] == false
    end
  end

  describe "real NIF: default-on scoring is wired" do
    @describetag :integration

    test "starting a node without explicit scoring opts succeeds" do
      # Pre-R2 this also succeeded — but `with_peer_score()` was never
      # called. Post-R2 it IS called with policy::* defaults. The smoke
      # test is that startup doesn't fail (the libp2p builder rejects
      # invalid scoring params with `Err`, which would surface as
      # `{:error, {:internal_error, "peer scoring: ..."}}` to Elixir).
      {:ok, node} =
        ExLibp2p.Node.start_link(
          native_module: ExLibp2p.Native.Nif,
          listen_addrs: ["/ip4/127.0.0.1/tcp/0"],
          enable_mdns: false
        )

      # Sanity: querying the score for a fake peer doesn't crash.
      # libp2p's gossipsub.peer_score() returns None for unknown peers,
      # which the NIF maps to 0.0.
      {:ok, peer_id} =
        ExLibp2p.PeerId.new("12D3KooWRPmBBCBTuGh1cnUuFVr35GYnm4bRXYsSB94TXJLAg4mA")

      assert {:ok, 0.0} = ExLibp2p.Gossipsub.peer_score(node, peer_id)

      ExLibp2p.Node.stop(node)
    end

    test "explicit opt-out via peer_score_disabled also succeeds" do
      {:ok, node} =
        ExLibp2p.Node.start_link(
          native_module: ExLibp2p.Native.Nif,
          listen_addrs: ["/ip4/127.0.0.1/tcp/0"],
          enable_mdns: false,
          gossipsub_peer_score_disabled: true
        )

      assert is_pid(node)
      ExLibp2p.Node.stop(node)
    end
  end
end
