defmodule ExLibp2p.Node.Config.Rendezvous do
  @moduledoc "Rendezvous discovery client + server roles."

  @enforce_keys []
  defstruct enable_client: false,
            enable_server: false

  @type t :: %__MODULE__{
          enable_client: boolean(),
          enable_server: boolean()
        }
end
