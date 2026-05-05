defmodule ExLibp2p.Keypair do
  @moduledoc """
  Ed25519 keypair management for libp2p node identity.

  A node's identity is derived from its keypair. Persisting the keypair
  ensures a stable `PeerId` across restarts.

  ## Usage

      # Generate a new keypair
      {:ok, keypair} = ExLibp2p.Keypair.generate()

      # Save to disk (sets file permissions to 0o600)
      :ok = ExLibp2p.Keypair.save!(keypair, "identity.key")

      # Load from disk
      {:ok, keypair} = ExLibp2p.Keypair.load("identity.key")

      # Use in node config
      {:ok, node} = ExLibp2p.Node.start_link(keypair: keypair)

  """

  @enforce_keys [:public_key, :peer_id]
  defstruct [:public_key, :peer_id, :protobuf_bytes]

  @typedoc "An Ed25519 keypair for libp2p identity."
  @type t :: %__MODULE__{
          public_key: binary(),
          peer_id: String.t(),
          protobuf_bytes: binary() | nil
        }

  @doc """
  Generates a new Ed25519 keypair.

  Returns `{:ok, keypair}` with the public key and derived peer ID.
  """
  @spec generate() :: {:ok, t()} | {:error, term()}
  def generate do
    case native_module().generate_keypair() do
      {:ok, public_key, peer_id, protobuf_bytes} ->
        {:ok,
         %__MODULE__{
           public_key: public_key,
           peer_id: peer_id,
           protobuf_bytes: protobuf_bytes
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Encodes a keypair to protobuf binary format for storage.

  The protobuf encoding is self-describing — it embeds the key type.
  """
  @spec to_protobuf(t()) :: {:ok, binary()} | {:error, term()}
  def to_protobuf(%__MODULE__{protobuf_bytes: bytes}) when is_binary(bytes) do
    {:ok, bytes}
  end

  def to_protobuf(%__MODULE__{}), do: {:error, :no_protobuf_data}

  def to_protobuf(_), do: {:error, :invalid_input}

  @doc """
  Decodes a keypair from protobuf binary format.
  """
  @spec from_protobuf(binary()) :: {:ok, t()} | {:error, :invalid_keypair}
  def from_protobuf(bytes) when is_binary(bytes) do
    case native_module().keypair_from_protobuf(bytes) do
      {:ok, public_key, peer_id} ->
        {:ok,
         %__MODULE__{
           public_key: public_key,
           peer_id: peer_id,
           protobuf_bytes: bytes
         }}

      {:error, _} ->
        {:error, :invalid_keypair}
    end
  end

  @doc """
  Saves a keypair to a file with restrictive permissions (0o600).

  Returns `:ok` or `{:error, reason}`.
  """
  @spec save(t(), Path.t()) :: :ok | {:error, term()}
  def save(%__MODULE__{protobuf_bytes: bytes}, path) when is_binary(bytes) do
    # (default impl `Storage.File` preserves the atomic-write + 0o600 idiom).
    ExLibp2p.Config.keypair_storage().write(path, bytes)
  end

  @doc """
  Saves a keypair to a file with restrictive permissions (0o600).

  Raises on file write errors.
  """
  @spec save!(t(), Path.t()) :: :ok
  def save!(%__MODULE__{} = keypair, path) do
    case save(keypair, path) do
      :ok -> :ok
      {:error, reason} -> raise "Failed to save keypair to #{path}: #{inspect(reason)}"
    end
  end

  @doc """
  Loads a keypair from a file.

  Returns `{:ok, keypair}` or `{:error, :file_not_found}`.
  """
  @spec load(Path.t()) :: {:ok, t()} | {:error, :file_not_found | :invalid_keypair}
  def load(path) do
    # Translation `:enoent` → `:file_not_found` stays here because it's the
    # high-level API contract; storage backends return raw POSIX errors.
    case ExLibp2p.Config.keypair_storage().read(path) do
      {:ok, bytes} -> from_protobuf(bytes)
      {:error, :enoent} -> {:error, :file_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Loads a keypair from a file, raising on failure.
  """
  @spec load!(Path.t()) :: t()
  def load!(path) do
    case load(path) do
      {:ok, keypair} ->
        keypair

      {:error, :file_not_found} ->
        raise File.Error, reason: :enoent, action: "read file", path: path

      {:error, reason} ->
        raise ArgumentError, "invalid keypair file: #{inspect(reason)}"
    end
  end

  # `ExLibp2p.Config` accessor (not `compile_env`). Pre-fix this was
  # `Application.compile_env`, which baked the value at module-attribute
  # time → integration tests that flip `:native_module` at runtime
  # silently kept the compile-time Mock binding. Runtime read makes the
  # test setup's `Application.put_env` actually take effect.
  defp native_module, do: ExLibp2p.Config.default_native_module()
end
