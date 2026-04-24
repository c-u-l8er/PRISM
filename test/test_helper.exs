# Ensure the test DB is fresh by running migrations
ExUnit.start(
  exclude: [
    :integration,
    # Live PRISM ↔ OS-011 tests require a running Graphonomous MCP
    # server (default http://127.0.0.1:4201/mcp, override via
    # GRAPHONOMOUS_LIVE_URL). Run explicitly with:
    #
    #     mix test --include live_os011
    live_os011: true
  ]
)

# Run migrations in shared mode so the migrator can access the DB
Ecto.Adapters.SQL.Sandbox.mode(Prism.Repo, {:shared, self()})

migrations_path = Path.join([File.cwd!(), "priv", "repo", "migrations"])

if File.dir?(migrations_path) do
  Ecto.Migrator.run(Prism.Repo, migrations_path, :up, all: true, log: false)
end

# Switch back to manual mode for test isolation
Ecto.Adapters.SQL.Sandbox.mode(Prism.Repo, :manual)
