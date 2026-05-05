defmodule ExLibp2p.StorageCapture do
  @moduledoc """
  In-test `ExLibp2p.Keypair.Storage` adapter that captures writes and
  serves pre-staged reads. Per-test isolation via an ETS-backed bucket
  keyed by path. Ensures DHT-persistence tests can assert "the file
  was written with these bytes" or "the import received these bytes"
  without touching the real filesystem.

  Test setup pattern:

      setup do
        ExLibp2p.StorageCapture.start()
        on_exit(fn -> ExLibp2p.StorageCapture.stop() end)
        :ok
      end

      test "..." do
        ExLibp2p.StorageCapture.stage("/path", <<...>>)        # pre-stage a read
        # ... run code under test ...
        assert ExLibp2p.StorageCapture.get("/path") == <<...>> # assert what was written
      end
  """

  @behaviour ExLibp2p.Keypair.Storage

  @table :ex_libp2p_storage_capture

  @doc "Initialize the ETS-backed capture table. Idempotent across tests."
  def start do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

      _ ->
        :ets.delete_all_objects(@table)
        @table
    end
  end

  @doc "Tear down the capture table."
  def stop do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _ -> :ets.delete(@table)
    end

    :ok
  end

  @doc "Pre-stage a value to be returned by `read/1` for `path`."
  def stage(path, bytes) when is_binary(path) and is_binary(bytes) do
    :ets.insert(@table, {path, bytes})
    :ok
  end

  @doc "Returns the bytes most recently written to `path`, or nil."
  def get(path) when is_binary(path) do
    case :ets.lookup(@table, path) do
      [{^path, bytes}] -> bytes
      [] -> nil
    end
  end

  @impl true
  def read(path) when is_binary(path) do
    case :ets.lookup(@table, path) do
      [{^path, bytes}] -> {:ok, bytes}
      [] -> {:error, :enoent}
    end
  end

  @impl true
  def write(path, bytes) when is_binary(path) and is_binary(bytes) do
    :ets.insert(@table, {path, bytes})
    :ok
  end
end
