defmodule ExLibp2p.KeypairTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.Keypair

  describe "generate/0" do
    test "generates a new Ed25519 keypair" do
      assert {:ok, %Keypair{} = kp} = Keypair.generate()
      assert is_binary(kp.public_key)
      assert is_binary(kp.peer_id)
      assert byte_size(kp.peer_id) >= 40
    end

    test "generates unique keypairs" do
      {:ok, kp1} = Keypair.generate()
      {:ok, kp2} = Keypair.generate()
      refute kp1.peer_id == kp2.peer_id
    end
  end

  describe "to_protobuf/1 and from_protobuf/1" do
    test "round-trips a keypair" do
      {:ok, original} = Keypair.generate()
      {:ok, encoded} = Keypair.to_protobuf(original)
      assert is_binary(encoded)

      {:ok, decoded} = Keypair.from_protobuf(encoded)
      assert decoded.peer_id == original.peer_id
    end

    test "from_protobuf rejects invalid data" do
      assert {:error, :invalid_keypair} = Keypair.from_protobuf(<<0, 1, 2, 3>>)
    end
  end

  describe "save!/2 and load/1" do
    @tag :tmp_dir
    test "persists and loads a keypair", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "test_key")
      {:ok, original} = Keypair.generate()

      assert :ok = Keypair.save!(original, path)
      assert File.exists?(path)

      assert {:ok, loaded} = Keypair.load(path)
      assert loaded.peer_id == original.peer_id
    end

    test "load returns error for missing file" do
      assert {:error, :file_not_found} =
               Keypair.load("/tmp/nonexistent_key_#{System.unique_integer()}")
    end

    @tag :tmp_dir
    test "save! sets restrictive permissions", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "restricted_key")
      {:ok, kp} = Keypair.generate()
      :ok = Keypair.save!(kp, path)

      %{mode: mode} = File.stat!(path)
      # Owner read+write only (0o600 = 0o100600, masked)
      assert Bitwise.band(mode, 0o777) == 0o600
    end
  end

  describe "load!/1" do
    @tag :tmp_dir
    test "returns keypair for valid file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "bang_key")
      {:ok, original} = Keypair.generate()
      :ok = Keypair.save!(original, path)

      loaded = Keypair.load!(path)
      assert loaded.peer_id == original.peer_id
    end

    test "raises for missing file" do
      assert_raise File.Error, fn ->
        Keypair.load!("/tmp/nonexistent_key_#{System.unique_integer()}")
      end
    end
  end
end
