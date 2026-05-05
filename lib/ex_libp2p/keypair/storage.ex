defmodule ExLibp2p.Keypair.Storage do
  @moduledoc """
  Behaviour for keypair persistence backends.

  The default production implementation is `ExLibp2p.Keypair.Storage.File`,
  which writes the protobuf-encoded keypair to disk with `0o600` permissions
  (libp2p Rule 12 — keypair files must be owner-readable only on POSIX).

  ## Implementations

    * `ExLibp2p.Keypair.Storage.File` — POSIX file storage with atomic write.
    * `ExLibp2p.Keypair.Storage.Mock` — auto-generated test mock via Mox.

  ## Configuration

      # config/config.exs (production default — implicit)
      config :ex_libp2p, ExLibp2p.Keypair, storage: ExLibp2p.Keypair.Storage.File

      # config/test.exs (Mox swap)
      config :ex_libp2p, ExLibp2p.Keypair, storage: ExLibp2p.Keypair.Storage.Mock

  Resolved at runtime via `ExLibp2p.Config.keypair_storage/0`.

  ## Atomic write contract

  `write/2` MUST be atomic with respect to concurrent readers — partial reads
  of an in-progress write are not allowed. The `File` implementation achieves
  this via write-to-`.tmp` + `chmod 0o600` + `rename`. Other implementations
  are free to use any equivalent atomicity mechanism (e.g., a transactional
  KV store) but must preserve the no-partial-read invariant.
  """

  @doc """
  Reads the keypair binary from `path`.

  Returns `{:ok, bytes}` or `{:error, reason}` where `reason` is the standard
  POSIX error atom (`:enoent`, `:eacces`, etc.) — translation to higher-level
  atoms (`:file_not_found`) happens in `ExLibp2p.Keypair.load/1`.
  """
  @callback read(path :: Path.t()) :: {:ok, binary()} | {:error, atom()}

  @doc """
  Writes `bytes` to `path` atomically with restrictive permissions.

  On POSIX targets the resulting file MUST be `0o600` (libp2p Rule 12).
  Returns `:ok` or `{:error, reason}` with a POSIX error atom.
  """
  @callback write(path :: Path.t(), bytes :: binary()) :: :ok | {:error, atom()}
end
