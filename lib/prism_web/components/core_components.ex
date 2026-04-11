defmodule PrismWeb.CoreComponents do
  @moduledoc """
  Minimal set of core components needed by the landing page.

  PRISM's web layer intentionally avoids importing the full generated
  Phoenix.Component library — the marketing site uses plain HEEx, and
  the leaderboard (future LiveView) will add components as needed.
  """
  use Phoenix.Component
end
