import Config

config :prism, Prism.Repo,
  database: Path.expand("~/.prism/prism_dev.db"),
  show_sensitive_data_on_connection_error: true
