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

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :cycle, :system, :run_id]

import_config "#{config_env()}.exs"
