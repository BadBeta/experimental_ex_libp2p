defmodule ExLibp2p.Telemetry do
  @moduledoc """
  Telemetry event definitions for ExLibp2p.

  All events are prefixed with `[:ex_libp2p, ...]`.

  ## Events

  ### Connection Events
  - `[:ex_libp2p, :connection, :established]` — new peer connected
  - `[:ex_libp2p, :connection, :closed]` — peer disconnected

  ### GossipSub Events
  - `[:ex_libp2p, :gossipsub, :message_received]` — message received
  - `[:ex_libp2p, :gossipsub, :message_published]` — message published

  ### DHT Events
  - `[:ex_libp2p, :dht, :query_completed]` — DHT query completed

  ### Health Events
  - `[:ex_libp2p, :health, :check]` — health check succeeded
  - `[:ex_libp2p, :health, :check_failed]` — health check failed

  ### Node Events
  - `[:ex_libp2p, :node, :started]` — node started
  - `[:ex_libp2p, :node, :stopped]` — node stopped

  ## Attaching Handlers

      :telemetry.attach_many(
        "my-handler",
        ExLibp2p.Telemetry.event_names(),
        &handle_event/4,
        nil
      )

  """

  @events [
    [:ex_libp2p, :connection, :established],
    [:ex_libp2p, :connection, :closed],
    [:ex_libp2p, :gossipsub, :message_received],
    [:ex_libp2p, :gossipsub, :message_published],
    [:ex_libp2p, :dht, :query_completed],
    [:ex_libp2p, :health, :check],
    [:ex_libp2p, :health, :check_failed],
    [:ex_libp2p, :node, :started],
    [:ex_libp2p, :node, :stopped]
  ]

  @doc "Returns all telemetry event names defined by ExLibp2p."
  @spec event_names() :: [[atom()]]
  def event_names, do: @events
end
