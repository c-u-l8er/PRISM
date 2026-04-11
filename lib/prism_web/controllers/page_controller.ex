defmodule PrismWeb.PageController do
  use PrismWeb, :controller

  def home(conn, _params) do
    render(conn, :home, page_title: "PRISM — Self-improving memory benchmark")
  end
end
