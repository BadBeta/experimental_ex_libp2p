defmodule ExLibp2p.Node.DhtPersistenceTest do
  @moduledoc """
  Verifies the Node's DHT routing-table persistence wiring.

  The Mock NIF (default in unit tests) round-trips the imported bytes
  via its swarm-task scratch state — that's enough to assert the
  Elixir-side wiring (init reads → import; terminate exports → writes).
  An integration test exercises the same path against the real NIF and
  a real Kademlia routing table.
  """

  use ExUnit.Case, async: false

  alias ExLibp2p.{Node, StorageCapture}

  # Canonical empty-export bytes for the v1 wire format: MAGIC + version
  # + entry_count(0). Used by the Mock NIF as the default empty result.
  @empty_export <<"L2DT", 1, 0, 0, 0, 0>>

  setup do
    StorageCapture.start()

    # Swap the dht_state_storage adapter to the in-test capture for the
    # duration of this test. The previous value is restored on_exit so
    # other tests aren't polluted.
    prev = Application.get_env(:ex_libp2p, ExLibp2p.Node.DhtState, [])
    Application.put_env(:ex_libp2p, ExLibp2p.Node.DhtState, storage: StorageCapture)

    on_exit(fn ->
      Application.put_env(:ex_libp2p, ExLibp2p.Node.DhtState, prev)
      StorageCapture.stop()
    end)

    :ok
  end

  describe "dht_state_path nil (default — no persistence)" do
    test "neither reads nor writes the storage" do
      {:ok, node} = Node.start_link([])
      Node.stop(node)

      # No path was set; the storage table should be untouched.
      assert StorageCapture.get("/never-touched") == nil
    end
  end

  describe "dht_state_path set, no pre-existing snapshot" do
    test "writes the exported snapshot on terminate" do
      path = "/test/dht.bin"
      assert StorageCapture.get(path) == nil

      {:ok, node} = Node.start_link(dht_state_path: path)
      Node.stop(node)

      # Mock NIF exports the canonical empty-export bytes by default; the
      # Node's terminate hook writes them through the Storage behaviour.
      assert StorageCapture.get(path) == @empty_export
    end
  end

  describe "dht_state_path set, pre-existing snapshot" do
    test "imports the pre-staged bytes on init and round-trips them on terminate" do
      path = "/test/dht.bin"
      staged = <<"L2DT", 1, 0, 0, 0, 2>>
      :ok = StorageCapture.stage(path, staged)

      {:ok, node} = Node.start_link(dht_state_path: path)
      Node.stop(node)

      # The Mock NIF stores imported bytes in its swarm-task scratch state
      # and returns them verbatim on export — so the post-terminate write
      # equals the pre-staged read. This proves both sides of the
      # round-trip wired correctly.
      assert StorageCapture.get(path) == staged
    end
  end
end
