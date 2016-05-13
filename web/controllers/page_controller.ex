defmodule GoonAuth.PageController do
  use GoonAuth.Web, :controller

  # If you need docs for this you are bad.
  def index(conn, _params) do
    render conn, "index.html"
  end
end
