defmodule GoonAuth.PageController do
  use GoonAuth.Web, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end
end
