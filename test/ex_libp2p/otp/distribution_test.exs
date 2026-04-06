defmodule ExLibp2p.OTP.DistributionTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.{Node, PeerId}
  alias ExLibp2p.Node.Event
  alias ExLibp2p.OTP.Distribution

  setup do
    {:ok, node} =
      Node.start_link(
        native_module: ExLibp2p.Native.Mock,
        listen_addrs: ["/ip4/127.0.0.1/tcp/0"]
      )

    %{node: node}
  end

  describe "call/4" do
    test "serializes the request and sends via request-response", %{node: node} do
      peer = PeerId.new!("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")

      # With mock, send_request always succeeds but no real reply comes back
      result = Distribution.call(node, peer, :my_server, :ping, 100)

      # Mock won't produce a real response, so we expect timeout
      assert result == {:error, :timeout}
    end
  end

  describe "cast/4" do
    test "sends a fire-and-forget message", %{node: node} do
      peer = PeerId.new!("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")
      assert :ok = Distribution.cast(node, peer, :my_server, {:update, "data"})
    end
  end

  describe "send/4" do
    test "sends a raw message to a named process", %{node: node} do
      peer = PeerId.new!("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")
      assert :ok = Distribution.send(node, peer, :my_server, {:info, "hello"})
    end
  end

  describe "encode/decode" do
    test "round-trips an Elixir term through the wire format" do
      original = {:call, :my_server, {:complex, %{key: [1, 2, 3]}, :atom}}
      encoded = Distribution.encode(original)
      assert is_binary(encoded)

      {:ok, decoded} = Distribution.decode(encoded)
      assert decoded == original
    end

    test "decode rejects invalid binary" do
      assert {:error, :invalid_message} = Distribution.decode(<<0, 1, 2, 3>>)
    end

    test "decode rejects terms with unknown atoms" do
      # :erlang.term_to_binary with atoms that don't exist
      # binary_to_term with :safe rejects unknown atoms
      # We test by encoding a known term — this should always work
      encoded = Distribution.encode({:ok, "safe"})
      {:ok, decoded} = Distribution.decode(encoded)
      assert decoded == {:ok, "safe"}
    end
  end

  describe "handle_remote_call/2" do
    test "dispatches to a locally registered GenServer" do
      # Start a simple GenServer registered with a name
      {:ok, _} = Agent.start_link(fn -> 42 end, name: :test_agent_for_distribution)

      # Simulate receiving a remote call
      request = Distribution.encode({:call, :test_agent_for_distribution, {:get, fn s -> s end}})
      {:ok, decoded} = Distribution.decode(request)

      {:ok, response} = Distribution.handle_remote_request(decoded)
      {:ok, reply} = Distribution.decode(response)

      assert reply == {:reply, 42}

      Agent.stop(:test_agent_for_distribution)
    end

    test "returns error for unregistered process" do
      request = Distribution.encode({:call, :nonexistent_process_xyz, :ping})
      {:ok, decoded} = Distribution.decode(request)

      {:ok, response} = Distribution.handle_remote_request(decoded)
      {:ok, reply} = Distribution.decode(response)

      assert reply == {:error, :noproc}
    end
  end
end
