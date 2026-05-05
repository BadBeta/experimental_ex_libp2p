defmodule ExLibp2p.Node.Config.RequestResponse do
  @moduledoc "Request-response RPC protocol: protocol name and per-request timeout."

  @enforce_keys []
  defstruct protocol_name: "/ex-libp2p/rpc/1.0.0",
            request_timeout_secs: 30

  @type t :: %__MODULE__{
          protocol_name: String.t(),
          request_timeout_secs: pos_integer()
        }
end
