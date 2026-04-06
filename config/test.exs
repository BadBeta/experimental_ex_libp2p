import Config

# Unit tests use the mock NIF — no Rust compilation needed.
# Integration tests override this per-test with native_module: ExLibp2p.Native.Nif.
config :ex_libp2p, native_module: ExLibp2p.Native.Mock
