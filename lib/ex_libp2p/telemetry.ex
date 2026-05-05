defmodule ExLibp2p.Telemetry do
  @moduledoc """
  Telemetry event catalog for ExLibp2p.

  All events are prefixed with `[:ex_libp2p, ...]`. The catalog is split into
  events that **fire today** (returned by `event_names/0`) and events on the
  **roadmap** (returned by `aspirational_event_names/0`). Subscribers wanting
  current coverage attach to `event_names/0`; tooling tracking the roadmap
  reads `aspirational_event_names/0`.

  ## Events fired today

  ### `:telemetry.span/3` (each fires `:start`, `:stop`, `:exception`)
  - `[:ex_libp2p, :node, :dial]` — outbound dial attempt
  - `[:ex_libp2p, :gossipsub, :publish]` — GossipSub publish

  ### `:telemetry.execute/3`
  - `[:ex_libp2p, :gossipsub, :subscribe]` — topic subscribe
  - `[:ex_libp2p, :gossipsub, :unsubscribe]` — topic unsubscribe
  - `[:ex_libp2p, :health, :check]` — health probe succeeded
  - `[:ex_libp2p, :health, :check_failed]` — health probe failed

  ## Roadmap events (not yet fired — listed for tooling/forward-compat)

  - `[:ex_libp2p, :connection, :established]` — peer connected
  - `[:ex_libp2p, :connection, :closed]` — peer disconnected
  - `[:ex_libp2p, :gossipsub, :message_received]` — inbound message
  - `[:ex_libp2p, :dht, :query_completed]` — DHT query result
  - `[:ex_libp2p, :node, :started]` — node successfully booted
  - `[:ex_libp2p, :node, :stopped]` — node terminated

  ## Attaching handlers

  Use `event_names/0` for production observability — these are stable.

      :telemetry.attach_many(
        "my-handler",
        ExLibp2p.Telemetry.event_names(),
        &handle_event/4,
        nil
      )

  See `ExLibp2p.Telemetry.Counters` for a built-in counter aggregator with
  Prometheus text-format rendering.
  """

  # Span events expand to start/stop/exception triplets. The catalog enumerates
  # the triplets explicitly so subscribers attach to the exact event names that
  # fire (telemetry's `:span` macro does NOT auto-expand for attachers).
  @span_events [
    [:ex_libp2p, :node, :dial],
    [:ex_libp2p, :gossipsub, :publish]
  ]

  @execute_events [
    [:ex_libp2p, :gossipsub, :subscribe],
    [:ex_libp2p, :gossipsub, :unsubscribe],
    [:ex_libp2p, :health, :check],
    [:ex_libp2p, :health, :check_failed]
  ]

  @aspirational_events [
    [:ex_libp2p, :connection, :established],
    [:ex_libp2p, :connection, :closed],
    [:ex_libp2p, :gossipsub, :message_received],
    [:ex_libp2p, :dht, :query_completed],
    [:ex_libp2p, :node, :started],
    [:ex_libp2p, :node, :stopped]
  ]

  @span_suffixes [:start, :stop, :exception]

  @doc """
  Returns the full list of telemetry event names that fire today.

  Span events are expanded to their `:start` / `:stop` / `:exception` triplets.
  Use this list with `:telemetry.attach_many/4`.
  """
  @spec event_names() :: [[atom()]]
  def event_names do
    span_expanded =
      for event <- @span_events, suffix <- @span_suffixes do
        event ++ [suffix]
      end

    span_expanded ++ @execute_events
  end

  @doc """
  Returns events that the catalog plans to emit but does NOT fire today.

  Use this for forward-compatibility tooling that wants to register
  subscribers ahead of the events being implemented.
  """
  @spec aspirational_event_names() :: [[atom()]]
  def aspirational_event_names, do: @aspirational_events
end
