defmodule PrismWeb.HealthController do
  use PrismWeb, :controller

  def index(conn, _params) do
    json(conn, %{
      status: "ok",
      app: "prism",
      spec: "OS-009",
      version: Application.spec(:prism, :vsn) |> to_string(),
      time: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end
end
