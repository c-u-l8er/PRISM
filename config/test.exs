import Config

config :prism, Prism.Repo,
  database: Path.expand("../prism_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :logger, level: :warning
