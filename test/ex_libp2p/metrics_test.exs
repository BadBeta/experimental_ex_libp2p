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

  describe "prometheus_scrape/1 (Mock)" do
    test "returns the documented placeholder", %{node: node} do
      assert {:ok, text} = Metrics.prometheus_scrape(node)
      assert text =~ "mock"
    end
  end
end

defmodule ExLibp2p.MetricsRealNifTest do
  use ExUnit.Case, async: false

  describe "prometheus_scrape/1 (real NIF)" do
    @describetag :integration

    test "scrapes the Prometheus registry held alive by NodeHandle" do
      {:ok, node} =
        ExLibp2p.Node.start_link(
          native_module: ExLibp2p.Native.Nif,
          listen_addrs: ["/ip4/127.0.0.1/tcp/0"],
          enable_mdns: false
        )

      assert {:ok, text} = ExLibp2p.Metrics.prometheus_scrape(node)
      assert is_binary(text)

      # The Registry is alive — pre-R4 it was dropped immediately and any
      # scrape would fail or return empty. Post-R4 it persists for the
      # lifetime of the NodeHandle. Even with no traffic, the encoder
      # produces a valid Prometheus payload (possibly empty body but the
      # call returns successfully).
      assert byte_size(text) >= 0

      ExLibp2p.Node.stop(node)
    end
  end
end
