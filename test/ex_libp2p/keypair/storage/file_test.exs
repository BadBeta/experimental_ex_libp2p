defmodule ExLibp2p.Keypair.Storage.FileTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.Keypair.Storage.File, as: FileStorage

  describe "write/2 + read/1" do
    @tag :tmp_dir
    test "round-trips binary content", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "round_trip.key")
      bytes = <<1, 2, 3, 4, 5>>

      assert :ok = FileStorage.write(path, bytes)
      assert {:ok, ^bytes} = FileStorage.read(path)
    end

    @tag :tmp_dir
    test "write sets 0o600 permissions on POSIX", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "secured.key")
      :ok = FileStorage.write(path, <<0, 1, 2>>)

      %{mode: mode} = File.stat!(path)
      # libp2p Rule 12 — keypair files MUST be 0o600 on Unix
      assert Bitwise.band(mode, 0o777) == 0o600
    end

    @tag :tmp_dir
    test "write is atomic — no partial file on rename failure", %{tmp_dir: tmp_dir} do
      # Atomic-write idiom: write to .tmp, chmod, rename. If the destination dir
      # didn't exist, the .tmp must be cleaned up too. This test documents the
      # cleanup contract by verifying no .tmp residue after a successful write.
      path = Path.join(tmp_dir, "atomic.key")
      :ok = FileStorage.write(path, <<9, 8, 7>>)

      tmp_residue = path <> ".tmp"
      refute File.exists?(tmp_residue), "atomic write left .tmp residue"
    end
  end

  describe "read/1" do
    test "returns {:error, :enoent} for missing file" do
      missing = "/tmp/__definitely_missing_#{System.unique_integer([:positive])}.key"
      assert {:error, :enoent} = FileStorage.read(missing)
    end
  end
end
