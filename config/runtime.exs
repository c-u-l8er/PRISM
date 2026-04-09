import Config

if config_env() == :prod do
  database_url = System.fetch_env!("DATABASE_URL")

  config :prism, Prism.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))
end

config :prism,
  generator_model: System.get_env("GENERATOR_MODEL", "claude-sonnet-4-20250514"),
  judge_model: System.get_env("JUDGE_MODEL", "gpt-4o"),
  runner_pool_size: String.to_integer(System.get_env("RUNNER_POOL_SIZE", "4"))
