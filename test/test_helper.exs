# Ensure the test DB is fresh by running migrations
ExUnit.start(exclude: [:integration])

# Run migrations in shared mode so the migrator can access the DB
Ecto.Adapters.SQL.Sandbox.mode(Prism.Repo, {:shared, self()})

migrations_path = Path.join([File.cwd!(), "priv", "repo", "migrations"])

if File.dir?(migrations_path) do
  Ecto.Migrator.run(Prism.Repo, migrations_path, :up, all: true, log: false)
end

# Switch back to manual mode for test isolation
Ecto.Adapters.SQL.Sandbox.mode(Prism.Repo, :manual)
