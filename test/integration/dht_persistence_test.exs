defmodule ExLibp2p.Integration.DhtPersistenceTest do
  @moduledoc """
  End-to-end test for DHT routing-table persistence against the real NIF.

  Exercises the full flow:
  1. Start a node with `dht_state_path:` set (Kademlia enabled).
  2. Stop the node — `terminate/2` exports the (initially empty) routing
     table via `kad_export_routing_table/1` and writes the bytes to
     disk via `Keypair.Storage.File`.
  3. Assert the file exists and decodes cleanly.
  4. Start a second node pointing at the same file — `init/1` reads the
     file and calls `kad_import_routing_table/2`. The node must boot
     without raising even when the routing table is empty.
  """
  use ExLibp2p.NifCase, async: false

  alias ExLibp2p.Node

  @tag :integration
  @tag :tmp_dir
  test "round-trip: export on stop, import on start", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "dht_state.bin")
    refute File.exists?(path)

    {:ok, node1} = start_test_node(enable_kademlia: true, dht_state_path: path)
    Node.stop(node1)

    # The file MUST exist after a clean stop.
    assert File.exists?(path), "expected #{path} to be written by Node.terminate/2"
    bytes = File.read!(path)

    # Sanity: file starts with the canonical "L2DT" magic + version 1
    # documented in `native/ex_libp2p_nif/src/dht_state.rs`.
    assert <<"L2DT", 1, _rest::binary>> = bytes

    # Second start with the same path must read + import without raising.
    {:ok, node2} = start_test_node(enable_kademlia: true, dht_state_path: path)
    assert {:ok, %ExLibp2p.PeerId{}} = Node.peer_id(node2)
    Node.stop(node2)

    # The file is rewritten on the second stop — content remains valid.
    assert File.exists?(path)
    assert <<"L2DT", 1, _rest::binary>> = File.read!(path)
  end
end
