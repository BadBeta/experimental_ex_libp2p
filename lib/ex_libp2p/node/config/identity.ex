defmodule ExLibp2p.Node.Config.Identity do
  @moduledoc "Identity-related config: persisted keypair bytes (libp2p Rule 12)."

  @enforce_keys []
  defstruct keypair_bytes: nil

  @type t :: %__MODULE__{keypair_bytes: binary() | nil}
end
