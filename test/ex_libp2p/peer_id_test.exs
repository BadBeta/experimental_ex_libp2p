defmodule ExLibp2p.PeerIdTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.PeerId

  doctest ExLibp2p.PeerId

  describe "new/1" do
    test "creates PeerId from valid base58 string" do
      raw = "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"
      assert {:ok, %PeerId{} = peer_id} = PeerId.new(raw)
      assert peer_id.id == raw
    end

    test "rejects empty string" do
      assert {:error, :invalid_peer_id} = PeerId.new("")
    end

    test "rejects string with invalid base58 characters" do
      assert {:error, :invalid_peer_id} = PeerId.new("invalid peer id with spaces!")
    end

    test "rejects nil" do
      assert {:error, :invalid_peer_id} = PeerId.new(nil)
    end

    test "rejects non-string input" do
      assert {:error, :invalid_peer_id} = PeerId.new(123)
    end

    test "rejects too-short string" do
      assert {:error, :invalid_peer_id} = PeerId.new("12D3")
    end
  end

  describe "new!/1" do
    test "returns PeerId for valid input" do
      raw = "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"
      assert %PeerId{id: ^raw} = PeerId.new!(raw)
    end

    test "raises for invalid input" do
      assert_raise ArgumentError, ~r/invalid peer ID/, fn ->
        PeerId.new!("")
      end
    end
  end

  describe "to_string/1" do
    test "returns the base58 string" do
      raw = "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"
      peer_id = PeerId.new!(raw)
      assert to_string(peer_id) == raw
    end
  end

  describe "inspect" do
    test "shows abbreviated form" do
      raw = "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"
      peer_id = PeerId.new!(raw)
      inspected = inspect(peer_id)
      assert inspected =~ "#PeerId<12D3KooW"
      assert inspected =~ ">"
      assert String.length(inspected) < String.length(raw)
    end
  end

  describe "equality" do
    test "same id is equal" do
      raw = "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"
      a = PeerId.new!(raw)
      b = PeerId.new!(raw)
      assert a == b
    end

    test "different id is not equal" do
      a = PeerId.new!("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")
      b = PeerId.new!("12D3KooWRPmBBCBTuGh1cnUuFVr35GYnm4bRXYsSB94TXJLAg4mA")
      refute a == b
    end
  end

  describe "Jason.Encoder" do
    test "encodes to JSON string" do
      raw = "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"
      peer_id = PeerId.new!(raw)
      assert Jason.encode!(peer_id) == ~s("#{raw}")
    end
  end
end
