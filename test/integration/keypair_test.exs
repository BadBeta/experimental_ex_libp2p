defmodule ExLibp2p.Integration.KeypairTest do
  @moduledoc "End-to-end tests for keypair generation, persistence, and node identity."
  use ExLibp2p.NifCase, async: false

  alias ExLibp2p.{Keypair, Node, PeerId}

  setup do
    # Ensure keypair tests use the real NIF, not the mock
    previous = Application.get_env(:ex_libp2p, :native_module)
    Application.put_env(:ex_libp2p, :native_module, ExLibp2p.Native.Nif)
    on_exit(fn -> Application.put_env(:ex_libp2p, :native_module, previous) end)
    :ok
  end

  @tag :integration
  test "generate creates a real Ed25519 keypair" do
    {:ok, kp} = Keypair.generate()

    assert is_binary(kp.public_key)
    assert byte_size(kp.public_key) > 0
    assert {:ok, %PeerId{}} = PeerId.new(kp.peer_id)
    assert is_binary(kp.protobuf_bytes)
    assert byte_size(kp.protobuf_bytes) > 0
  end

  @tag :integration
  test "generated keypairs are unique" do
    keypairs = for _i <- 1..5, do: elem(Keypair.generate(), 1)
    ids = Enum.map(keypairs, & &1.peer_id)
    assert length(Enum.uniq(ids)) == 5
  end

  @tag :integration
  test "protobuf round-trip preserves identity" do
    {:ok, original} = Keypair.generate()
    {:ok, encoded} = Keypair.to_protobuf(original)
    {:ok, decoded} = Keypair.from_protobuf(encoded)

    assert decoded.peer_id == original.peer_id
    assert decoded.public_key == original.public_key
  end

  @tag :integration
  @tag :tmp_dir
  test "save and load from disk", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "identity.key")

    {:ok, original} = Keypair.generate()
    :ok = Keypair.save!(original, path)

    assert File.exists?(path)
    %{mode: mode} = File.stat!(path)
    assert Bitwise.band(mode, 0o777) == 0o600

    {:ok, loaded} = Keypair.load(path)
    assert loaded.peer_id == original.peer_id
  end

  @tag :integration
  @tag :tmp_dir
  test "node started with persisted keypair has stable peer ID", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "node_identity.key")

    {:ok, kp} = Keypair.generate()
    :ok = Keypair.save!(kp, path)

    {:ok, loaded} = Keypair.load(path)

    {:ok, node} =
      start_test_node(keypair_bytes: loaded.protobuf_bytes)

    {:ok, node_peer_id} = Node.peer_id(node)
    assert to_string(node_peer_id) == kp.peer_id

    Node.stop(node)
  end

  @tag :integration
  test "from_protobuf rejects garbage data" do
    assert {:error, :invalid_keypair} = Keypair.from_protobuf(<<0, 1, 2, 3, 4, 5>>)
    assert {:error, :invalid_keypair} = Keypair.from_protobuf(:crypto.strong_rand_bytes(64))
  end
end
