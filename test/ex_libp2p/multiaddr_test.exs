defmodule ExLibp2p.MultiaddrTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.{Multiaddr, PeerId}

  doctest ExLibp2p.Multiaddr

  describe "new/1" do
    test "creates Multiaddr from valid TCP address" do
      raw = "/ip4/127.0.0.1/tcp/4001"
      assert {:ok, %Multiaddr{} = addr} = Multiaddr.new(raw)
      assert addr.address == raw
    end

    test "accepts QUIC address" do
      raw = "/ip4/0.0.0.0/udp/4001/quic-v1"
      assert {:ok, %Multiaddr{}} = Multiaddr.new(raw)
    end

    test "accepts address with p2p component" do
      raw = "/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"
      assert {:ok, %Multiaddr{}} = Multiaddr.new(raw)
    end

    test "accepts DNS address" do
      raw = "/dns4/bootstrap.libp2p.io/tcp/4001"
      assert {:ok, %Multiaddr{}} = Multiaddr.new(raw)
    end

    test "accepts WebSocket address" do
      raw = "/ip4/127.0.0.1/tcp/4001/ws"
      assert {:ok, %Multiaddr{}} = Multiaddr.new(raw)
    end

    test "rejects empty string" do
      assert {:error, :invalid_multiaddr} = Multiaddr.new("")
    end

    test "rejects string not starting with /" do
      assert {:error, :invalid_multiaddr} = Multiaddr.new("not a multiaddr")
    end

    test "rejects nil" do
      assert {:error, :invalid_multiaddr} = Multiaddr.new(nil)
    end

    test "rejects non-string input" do
      assert {:error, :invalid_multiaddr} = Multiaddr.new(123)
    end
  end

  describe "new!/1" do
    test "returns Multiaddr for valid input" do
      raw = "/ip4/127.0.0.1/tcp/4001"
      assert %Multiaddr{address: ^raw} = Multiaddr.new!(raw)
    end

    test "raises for invalid input" do
      assert_raise ArgumentError, ~r/invalid multiaddr/, fn ->
        Multiaddr.new!("")
      end
    end
  end

  describe "to_string/1" do
    test "returns the address string" do
      raw = "/ip4/127.0.0.1/tcp/4001"
      addr = Multiaddr.new!(raw)
      assert to_string(addr) == raw
    end
  end

  describe "inspect" do
    test "shows readable form" do
      raw = "/ip4/127.0.0.1/tcp/4001"
      addr = Multiaddr.new!(raw)
      assert inspect(addr) == "#Multiaddr</ip4/127.0.0.1/tcp/4001>"
    end
  end

  describe "with_p2p/2" do
    test "appends p2p component" do
      addr = Multiaddr.new!("/ip4/127.0.0.1/tcp/4001")
      peer_id = PeerId.new!("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")
      result = Multiaddr.with_p2p(addr, peer_id)
      assert to_string(result) =~ "/p2p/12D3KooW"
    end
  end

  describe "Jason.Encoder" do
    test "encodes to JSON string" do
      raw = "/ip4/127.0.0.1/tcp/4001"
      addr = Multiaddr.new!(raw)
      assert Jason.encode!(addr) == ~s("#{raw}")
    end
  end
end
