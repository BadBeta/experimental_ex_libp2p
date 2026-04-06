import Config

# Default to real NIF in all environments
config :ex_libp2p, native_module: ExLibp2p.Native.Nif

import_config "#{config_env()}.exs"
