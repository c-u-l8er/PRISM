import Config

if config_env() == :prod do
  # SQLite on the mounted Fly volume (prism_data → /app/data)
  database_path =
    System.get_env("DATABASE_PATH") || "/app/data/prism.db"

  config :prism, Prism.Repo,
    database: database_path,
    journal_mode: :wal,
    cache_size: -64_000,
    temp_store: :memory,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "5"))

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs; you can generate a fresh one
  # with `mix phx.gen.secret`.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      Run `mix phx.gen.secret` to generate one and set it on Fly.
      """

  host = System.get_env("PHX_HOST") || "prism-eval.fly.dev"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :prism, PrismWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces for Fly's internal proxy.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    server: true
end

config :prism,
  generator_model: System.get_env("GENERATOR_MODEL", "claude-sonnet-4-20250514"),
  judge_model: System.get_env("JUDGE_MODEL", "gpt-4o"),
  runner_pool_size: String.to_integer(System.get_env("RUNNER_POOL_SIZE", "4"))
