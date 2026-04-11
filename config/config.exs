import Config

config :prism, ecto_repos: [Prism.Repo]

# Default to SQLite for local development
config :prism, Prism.Repo,
  database: Path.expand("~/.prism/prism.db"),
  journal_mode: :wal,
  cache_size: -64000,
  temp_store: :memory,
  pool_size: 1

config :prism,
  generator_model: "claude-sonnet-4-20250514",
  judge_model: "gpt-4o",
  runner_pool_size: 4,
  storage_backend: :sqlite

# Phoenix endpoint — serves the PRISM marketing site and JSON APIs
config :prism, PrismWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PrismWeb.ErrorHTML, json: PrismWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Prism.PubSub,
  live_view: [signing_salt: "prism-os009-lv"]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :cycle, :system, :run_id]

import_config "#{config_env()}.exs"
