import Config

# Production uses Postgres (Supabase)
# Override adapter and connection in runtime.exs via DATABASE_URL

# Do not print debug messages in production
config :logger, level: :info

# Runtime production endpoint configuration is in runtime.exs so that
# SECRET_KEY_BASE, PHX_HOST, and the port can come from Fly env vars.
# Static assets are served directly from priv/static/assets without
# a precomputed manifest — there's no esbuild/tailwind pipeline yet.
