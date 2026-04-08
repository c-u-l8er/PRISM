import Config

config :prism, Prism.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "10")),
  ssl: true,
  ssl_opts: [verify: :verify_none]

config :prism,
  generator_model: System.get_env("GENERATOR_MODEL", "claude-sonnet-4-20250514"),
  judge_model: System.get_env("JUDGE_MODEL", "gpt-4o"),
  runner_pool_size: String.to_integer(System.get_env("RUNNER_POOL_SIZE", "4"))
