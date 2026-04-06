defmodule ExLibp2p.Gossipsub.PeerScoreTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.Gossipsub.PeerScore
  alias ExLibp2p.Gossipsub.PeerScore.{Thresholds, TopicParams}

  describe "PeerScore.new/1" do
    test "creates with defaults" do
      params = PeerScore.new()
      assert params.ip_colocation_factor_weight == -53.0
      assert params.behaviour_penalty_decay == 0.986
    end

    test "accepts overrides" do
      params = PeerScore.new(ip_colocation_factor_weight: -100.0)
      assert params.ip_colocation_factor_weight == -100.0
    end
  end

  describe "Thresholds.new/1" do
    test "creates with Ethereum beacon chain defaults" do
      thresholds = Thresholds.new()
      assert thresholds.gossip_threshold == -4000.0
      assert thresholds.publish_threshold == -8000.0
      assert thresholds.graylist_threshold == -16_000.0
    end

    test "accepts overrides" do
      thresholds = Thresholds.new(gossip_threshold: -2000.0)
      assert thresholds.gossip_threshold == -2000.0
    end
  end

  describe "TopicParams.new/1" do
    test "creates with defaults" do
      params = TopicParams.new()
      assert params.topic_weight == 1.0
      assert params.invalid_message_deliveries_weight == -140.0
    end

    test "accepts overrides" do
      params = TopicParams.new(topic_weight: 2.0)
      assert params.topic_weight == 2.0
    end
  end
end
