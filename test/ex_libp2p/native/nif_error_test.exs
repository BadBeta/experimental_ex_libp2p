defmodule ExLibp2p.Native.NifErrorTest do
  @moduledoc """
  Verifies the typed-error shape introduced by R1. The Rust-side `NifError`
  enum encodes as `{error_atom, human_readable_string}` tuples on the
  Elixir side.

  Mock NIF tests stay in `mock_test.exs`; THIS file exercises the real
  Rust NIF by hitting an error path that doesn't require a running swarm.
  Tag `:integration` so it runs only with `EX_LIBP2P_BUILD=1`.
  """
  use ExUnit.Case, async: true

  @moduletag :integration

  alias ExLibp2p.Native.Nif

  describe "keypair_from_protobuf typed errors" do
    test "rejects oversize input with InputTooLarge typed error" do
      # MAX_KEYPAIR_BYTES is 4 KiB on the Rust side. A 5 KiB binary is
      # cheap to construct and comfortably over the limit.
      oversize = :binary.copy(<<0>>, 5 * 1024)
      assert {:error, {:input_too_large, msg}} = Nif.keypair_from_protobuf(oversize)
      assert msg =~ ~r/got \d+ bytes/
      assert msg =~ ~r/max 4096/
    end

    test "rejects malformed input with InvalidKeypair typed error" do
      # Valid size but garbage bytes — libp2p protobuf decoder rejects.
      garbage = <<1, 2, 3, 4, 5>>
      assert {:error, {:invalid_keypair, msg}} = Nif.keypair_from_protobuf(garbage)
      assert is_binary(msg)
      refute msg == ""
    end

    test "round-trips a real generated keypair" do
      assert {:ok, _pub, peer_id, proto_bytes} = Nif.generate_keypair()
      assert is_binary(proto_bytes)
      assert {:ok, _pub2, ^peer_id} = Nif.keypair_from_protobuf(proto_bytes)
    end
  end
end
