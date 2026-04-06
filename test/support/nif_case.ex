defmodule ExLibp2p.NifCase do
  @moduledoc """
  ExUnit case template for integration tests that use the real NIF.

  These tests require the Rust NIF to be compiled and loaded.
  Run with: `mix test --include integration`
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import ExLibp2p.NifCase

      @moduletag :integration
    end
  end

  @doc "Starts a node with the real NIF (or mock if NIF not loaded)."
  def start_test_node(opts \\ []) do
    defaults = [
      listen_addrs: ["/ip4/127.0.0.1/tcp/0"],
      enable_mdns: false,
      idle_connection_timeout_secs: 30
    ]

    merged = Keyword.merge(defaults, opts)

    # Integration tests always use the real NIF — no silent mock fallback.
    # If the NIF isn't compiled, the test should fail explicitly.
    ExLibp2p.Node.start_link(Keyword.put(merged, :native_module, ExLibp2p.Native.Nif))
  end
end
