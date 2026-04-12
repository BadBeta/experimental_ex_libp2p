defmodule ExLibp2p.OTP.Distribution do
  @moduledoc """
  Transparent OTP message passing over libp2p.

  Provides `call/5`, `cast/4`, and `send/4` for communicating with
  GenServers on remote peers, using the same patterns as distributed Erlang
  but over libp2p's encrypted transport.

  ## Security

  All messages are encrypted in transit via Noise XX (X25519 + ChaChaPoly).
  Authentication is by PeerId (Ed25519 public key hash). This is an open
  mesh — any connected peer can call any registered GenServer.

  ## Addressing

  Remote processes are addressed by `{registered_name, peer_id}`:

      peer = ExLibp2p.PeerId.new!("12D3KooW...")

      # Synchronous call — blocks until reply or timeout
      {:ok, result} = ExLibp2p.OTP.Distribution.call(node, peer, :my_server, :ping)

      # Asynchronous cast — fire and forget
      :ok = ExLibp2p.OTP.Distribution.cast(node, peer, :my_server, {:update, data})

      # Raw send — sends to the process mailbox
      :ok = ExLibp2p.OTP.Distribution.send(node, peer, :my_server, {:info, msg})

  ## Error Handling

  Calls return `{:ok, reply}` or `{:error, reason}`:
  - `{:error, :timeout}` — no response within the deadline
  - `{:error, :unreachable}` — peer is not connected
  - `{:error, :noproc}` — the named process doesn't exist on the remote peer
  - `{:error, :request_failed}` — request-response protocol error

  The caller decides how to handle failures — no automatic retries.

  ## Wire Format

  Messages are serialized with `:erlang.term_to_binary/2` using compressed
  format, and deserialized with `:erlang.binary_to_term/2` using the `:safe`
  option (rejects unknown atoms, prevents atom table exhaustion from
  untrusted peers).

  ## Handling Incoming Calls

  To serve remote calls, start `ExLibp2p.OTP.Distribution.Server` as part of
  your supervision tree. It automatically handles inbound requests by
  dispatching to locally registered processes.
  """

  alias ExLibp2p.{Node, PeerId, RequestResponse}

  @call_timeout 5_000

  @doc """
  Calls a named GenServer on a remote peer. Blocks until reply or timeout.

  Returns `{:ok, reply}` or `{:error, reason}`.

  ## Examples

      {:ok, result} = ExLibp2p.OTP.Distribution.call(node, peer_id, :my_server, :ping)
      {:ok, result} = ExLibp2p.OTP.Distribution.call(node, peer_id, :my_server, :ping, 10_000)

  """
  @spec call(GenServer.server(), PeerId.t(), atom(), term(), non_neg_integer()) ::
          {:ok, term()} | {:error, :timeout | :unreachable | :noproc | :request_failed}
  def call(node, %PeerId{} = peer, name, message, timeout \\ @call_timeout)
      when is_atom(name) do
    payload = encode({:call, name, message})

    case RequestResponse.send_request(node, peer, payload) do
      {:ok, _request_id} ->
        receive do
          {:libp2p, :outbound_response, %Node.Event.OutboundResponse{data: response_data}} ->
            case decode(response_data) do
              {:ok, {:reply, reply}} -> {:ok, reply}
              {:ok, {:error, reason}} -> {:error, reason}
              {:error, _} -> {:error, :invalid_response}
            end
        after
          timeout -> {:error, :timeout}
        end

      {:error, _} ->
        {:error, :unreachable}
    end
  end

  @doc """
  Casts a message to a named GenServer on a remote peer. Fire and forget.

  Returns `:ok` immediately. No confirmation of delivery.
  """
  @spec cast(GenServer.server(), PeerId.t(), atom(), term()) :: :ok
  def cast(node, %PeerId{} = peer, name, message) when is_atom(name) do
    payload = encode({:cast, name, message})
    RequestResponse.send_request(node, peer, payload)
    :ok
  end

  @doc """
  Sends a raw message to a named process on a remote peer. Fire and forget.

  The message arrives in the remote process's `handle_info/2`.
  """
  @spec send(GenServer.server(), PeerId.t(), atom(), term()) :: :ok
  def send(node, %PeerId{} = peer, name, message) when is_atom(name) do
    payload = encode({:send, name, message})
    RequestResponse.send_request(node, peer, payload)
    :ok
  end

  @doc """
  Handles an inbound remote request by dispatching to the local process.

  Called by `ExLibp2p.OTP.Distribution.Server` when a request arrives.
  Returns `{:ok, response_binary}` with the encoded reply.
  """
  @spec handle_remote_request(tuple()) :: {:ok, binary()}
  def handle_remote_request({:call, name, message}) do
    case whereis(name) do
      nil ->
        {:ok, encode({:error, :noproc})}

      pid ->
        response =
          case safe_call(pid, message) do
            {:ok, reply} -> encode({:reply, reply})
            {:error, reason} -> encode({:error, reason})
          end

        {:ok, response}
    end
  end

  def handle_remote_request({:cast, name, message}) do
    case whereis(name) do
      nil -> :ok
      pid -> GenServer.cast(pid, message)
    end

    {:ok, encode({:reply, :ok})}
  end

  def handle_remote_request({:send, name, message}) do
    case whereis(name) do
      nil -> :ok
      pid -> Kernel.send(pid, message)
    end

    {:ok, encode({:reply, :ok})}
  end

  @doc """
  Encodes an Elixir term for transmission over the wire.

  Uses `:erlang.term_to_binary/2` with minor compression.
  """
  @spec encode(term()) :: binary()
  def encode(term) do
    :erlang.term_to_binary(term, [:compressed])
  end

  @doc """
  Decodes a binary received from the wire into an Elixir term.

  Uses `:safe` mode to reject unknown atoms — prevents atom table
  exhaustion from untrusted peers.
  """
  # Maximum payload size (1 MB) — prevents memory exhaustion from oversized messages.
  @max_payload_bytes 1_048_576

  @spec decode(binary()) :: {:ok, term()} | {:error, :invalid_message | :payload_too_large}
  def decode(binary) when is_binary(binary) and byte_size(binary) > @max_payload_bytes do
    {:error, :payload_too_large}
  end

  def decode(binary) when is_binary(binary) do
    {:ok, :erlang.binary_to_term(binary, [:safe])}
  rescue
    # binary_to_term raises ArgumentError on malformed input.
    # This is a system boundary (untrusted network data) — the one
    # legitimate use of rescue in this module.
    ArgumentError -> {:error, :invalid_message}
  end

  # Resolve a registered name to a PID, returning nil if not found.
  defp whereis(name) when is_atom(name), do: Process.whereis(name)
  defp whereis({:via, registry, key}), do: GenServer.whereis({:via, registry, key})

  # Call a GenServer by PID with ok/error return instead of exit.
  defp safe_call(pid, message) do
    {:ok, GenServer.call(pid, message, @call_timeout)}
  catch
    :exit, {:noproc, _} -> {:error, :noproc}
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, reason -> {:error, {:exit, inspect(reason)}}
  end
end
