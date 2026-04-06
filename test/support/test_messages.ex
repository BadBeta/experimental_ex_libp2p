defmodule ExLibp2p.TestMessages do
  @moduledoc """
  Structured message types for integration/stress tests.

  These mirror real-world usage where nodes exchange typed, serialized
  structs over GossipSub topics.
  """

  defmodule ChatMessage do
    @moduledoc false
    @derive Jason.Encoder
    @enforce_keys [:from, :text, :timestamp]
    defstruct [:from, :text, :timestamp, :reply_to]

    @type t :: %__MODULE__{
            from: String.t(),
            text: String.t(),
            timestamp: integer(),
            reply_to: String.t() | nil
          }

    def new(from, text, opts \\ []) do
      %__MODULE__{
        from: from,
        text: text,
        timestamp: System.monotonic_time(:millisecond),
        reply_to: Keyword.get(opts, :reply_to)
      }
    end

    def decode(binary) when is_binary(binary) do
      case Jason.decode(binary) do
        {:ok, %{"from" => from, "text" => text, "timestamp" => ts} = map} ->
          {:ok,
           %__MODULE__{
             from: from,
             text: text,
             timestamp: ts,
             reply_to: Map.get(map, "reply_to")
           }}

        _ ->
          {:error, :invalid_chat_message}
      end
    end
  end

  defmodule SensorReading do
    @moduledoc false
    @derive Jason.Encoder
    @enforce_keys [:node_id, :sensor, :value, :unit]
    defstruct [:node_id, :sensor, :value, :unit, :sequence]

    @type t :: %__MODULE__{
            node_id: String.t(),
            sensor: String.t(),
            value: float(),
            unit: String.t(),
            sequence: non_neg_integer() | nil
          }

    def new(node_id, sensor, value, unit, opts \\ []) do
      %__MODULE__{
        node_id: node_id,
        sensor: sensor,
        value: value,
        unit: unit,
        sequence: Keyword.get(opts, :sequence)
      }
    end

    def decode(binary) when is_binary(binary) do
      case Jason.decode(binary) do
        {:ok, %{"node_id" => nid, "sensor" => s, "value" => v, "unit" => u} = map} ->
          {:ok,
           %__MODULE__{
             node_id: nid,
             sensor: s,
             value: v,
             unit: u,
             sequence: Map.get(map, "sequence")
           }}

        _ ->
          {:error, :invalid_sensor_reading}
      end
    end
  end

  defmodule BlockAnnouncement do
    @moduledoc false
    @derive Jason.Encoder
    @enforce_keys [:block_hash, :height, :producer, :tx_count]
    defstruct [:block_hash, :height, :producer, :tx_count, :parent_hash, :timestamp]

    @type t :: %__MODULE__{
            block_hash: String.t(),
            height: non_neg_integer(),
            producer: String.t(),
            tx_count: non_neg_integer(),
            parent_hash: String.t() | nil,
            timestamp: integer() | nil
          }

    def new(producer, height, opts \\ []) do
      hash = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

      %__MODULE__{
        block_hash: hash,
        height: height,
        producer: producer,
        tx_count: Keyword.get(opts, :tx_count, 0),
        parent_hash: Keyword.get(opts, :parent_hash),
        timestamp: System.monotonic_time(:millisecond)
      }
    end

    def decode(binary) when is_binary(binary) do
      case Jason.decode(binary) do
        {:ok,
         %{
           "block_hash" => bh,
           "height" => h,
           "producer" => p,
           "tx_count" => tc
         } = map} ->
          {:ok,
           %__MODULE__{
             block_hash: bh,
             height: h,
             producer: p,
             tx_count: tc,
             parent_hash: Map.get(map, "parent_hash"),
             timestamp: Map.get(map, "timestamp")
           }}

        _ ->
          {:error, :invalid_block_announcement}
      end
    end
  end

  @doc "Encode any test message struct to binary for publishing."
  @spec encode!(struct()) :: binary()
  def encode!(msg), do: Jason.encode!(msg)

  @doc "Decode a binary into the appropriate struct by trying each type."
  @spec decode(binary()) :: {:ok, struct()} | {:error, :unknown_message}
  def decode(binary) do
    with {:error, _} <- ChatMessage.decode(binary),
         {:error, _} <- SensorReading.decode(binary),
         {:error, _} <- BlockAnnouncement.decode(binary) do
      {:error, :unknown_message}
    end
  end
end
