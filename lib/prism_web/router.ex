defmodule PrismWeb.Router do
  use PrismWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PrismWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"content-security-policy" => "default-src 'self' 'unsafe-inline' data: https:"}
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PrismWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/api", PrismWeb do
    pipe_through :api

    get "/leaderboard", LeaderboardController, :index
    get "/health", HealthController, :index
  end
end
