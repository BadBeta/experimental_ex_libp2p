defmodule ExLibp2p.HealthTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.Health

  setup do
    {:ok, node} =
      ExLibp2p.Node.start_link(
        native_module: ExLibp2p.Native.Mock,
        listen_addrs: ["/ip4/127.0.0.1/tcp/0"]
      )

    %{node: node}
  end

  describe "start_link/1" do
    test "starts a health check process", %{node: node} do
      {:ok, pid} = Health.start_link(node: node, interval: 60_000)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "check/1" do
    test "returns health status", %{node: node} do
      {:ok, health} = Health.start_link(node: node, interval: 60_000)
      assert {:ok, status} = Health.check(health)
      assert is_map(status)
      assert Map.has_key?(status, :peer_id)
      assert Map.has_key?(status, :connected_peers)
      assert Map.has_key?(status, :listening_addrs)
      GenServer.stop(health)
    end
  end
end
