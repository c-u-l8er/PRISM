import Config

config :prism, ecto_repos: [Prism.Repo]

config :prism, Prism.Repo,
  database: "prism_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432

config :prism,
  generator_model: "claude-sonnet-4-20250514",
  judge_model: "gpt-4o",
  runner_pool_size: 4

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :cycle, :system, :run_id]

import_config "#{config_env()}.exs"
