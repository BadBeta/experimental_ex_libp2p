defmodule ExLibp2p.MetricsTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.{Metrics, Node}

  setup do
    {:ok, node} =
      Node.start_link(
        native_module: ExLibp2p.Native.Mock,
        listen_addrs: ["/ip4/127.0.0.1/tcp/0"]
      )

    %{node: node}
  end

  describe "bandwidth/1" do
    test "returns bandwidth stats", %{node: node} do
      assert {:ok, %{bytes_in: bytes_in, bytes_out: bytes_out}} = Metrics.bandwidth(node)
      assert is_integer(bytes_in)
      assert is_integer(bytes_out)
    end
  end
end
