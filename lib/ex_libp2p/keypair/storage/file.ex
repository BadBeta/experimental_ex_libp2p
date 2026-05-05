defmodule ExLibp2p.Keypair.Storage.File do
  @moduledoc """
  POSIX file implementation of `ExLibp2p.Keypair.Storage`.

  `write/2` uses the atomic-write idiom (write to `<path>.tmp`, `chmod 0o600`,
  `rename` to final path) so concurrent readers never observe a partial file.

  See libp2p Rule 12 — keypair files MUST be `0o600` on Unix.
  """

  @behaviour ExLibp2p.Keypair.Storage

  @impl true
  def read(path), do: File.read(path)

  @impl true
  # seeing partial state; chmod-before-rename ensures perms are correct on first sight.
  def write(path, bytes) when is_binary(bytes) do
    tmp_path = path <> ".tmp"

    with :ok <- File.write(tmp_path, bytes),
         :ok <- File.chmod(tmp_path, 0o600),
         :ok <- File.rename(tmp_path, path) do
      :ok
    else
      {:error, reason} ->
        # Best-effort cleanup — ignore the rm result; if the rename succeeded
        # there's no .tmp to remove, and if rm fails it's a separate problem.
        _ = File.rm(tmp_path)
        {:error, reason}
    end
  end
end
