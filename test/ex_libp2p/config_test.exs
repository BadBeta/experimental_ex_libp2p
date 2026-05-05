defmodule ExLibp2p.ConfigTest do
  # async: false — these tests mutate global :ex_libp2p Application env.
  use ExUnit.Case, async: false

  alias ExLibp2p.Config

  setup do
    # Capture and restore each app-env key the suite mutates, so tests start clean
    # and leave no residue for sibling test modules.
    original_native = Application.get_env(:ex_libp2p, :native_module)
    original_keypair = Application.get_env(:ex_libp2p, ExLibp2p.Keypair)
    original_tracker = Application.get_env(:ex_libp2p, ExLibp2p.OTP.TaskTracker)

    on_exit(fn ->
      restore(:native_module, original_native)
      restore(ExLibp2p.Keypair, original_keypair)
      restore(ExLibp2p.OTP.TaskTracker, original_tracker)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:ex_libp2p, key)
  defp restore(key, value), do: Application.put_env(:ex_libp2p, key, value)

  describe "default_native_module/0" do
    test "returns the configured native module from app env" do
      Application.put_env(:ex_libp2p, :native_module, ExLibp2p.Native.Mock)
      assert Config.default_native_module() == ExLibp2p.Native.Mock
    end

    test "falls back to ExLibp2p.Native.Nif when app env is unset" do
      Application.delete_env(:ex_libp2p, :native_module)
      assert Config.default_native_module() == ExLibp2p.Native.Nif
    end
  end

  describe "keypair_storage/0" do
    test "returns the configured storage module" do
      Application.put_env(:ex_libp2p, ExLibp2p.Keypair, storage: ExLibp2p.Keypair.Storage.File)

      assert Config.keypair_storage() == ExLibp2p.Keypair.Storage.File
    end

    test "falls back to ExLibp2p.Keypair.Storage.File when app env is unset" do
      Application.delete_env(:ex_libp2p, ExLibp2p.Keypair)
      assert Config.keypair_storage() == ExLibp2p.Keypair.Storage.File
    end
  end

  describe "task_tracker_clock/0" do
    test "returns the configured clock module" do
      Application.put_env(:ex_libp2p, ExLibp2p.OTP.TaskTracker, clock: ExLibp2p.Clock.System)

      assert Config.task_tracker_clock() == ExLibp2p.Clock.System
    end

    test "falls back to ExLibp2p.Clock.System when app env is unset" do
      Application.delete_env(:ex_libp2p, ExLibp2p.OTP.TaskTracker)
      assert Config.task_tracker_clock() == ExLibp2p.Clock.System
    end
  end
end
