defmodule Prism.Repo do
  use Ecto.Repo,
    otp_app: :prism,
    adapter: Ecto.Adapters.SQLite3
end
