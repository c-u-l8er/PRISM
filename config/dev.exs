import Config

config :prism, Prism.Repo,
  database: Path.expand("~/.prism/prism_dev.db"),
  show_sensitive_data_on_connection_error: true

# For development, we disable any cache and enable debugging and
# code reloading. The watchers are empty because PRISM serves a
# single pre-built CSS file directly from priv/static/assets/.
config :prism, PrismWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev-prism-secret-key-base-00000000000000000000000000000000000000",
  watchers: [],
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/prism_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Include HEEx debug annotations in rendered markup
config :phoenix_live_view,
  debug_heex_annotations: true,
  enable_expensive_runtime_checks: true
