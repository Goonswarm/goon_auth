defmodule GoonAuth.PageController do
  use GoonAuth.Web, :controller
  import GoonAuth.Auth, only: [authenticate: 1]

  # If you need docs for this you are bad.
  def index(conn, _params) do
    render(conn, "index.html")
  end

  # Display a welcome page to newly registered users.
  def welcome(conn, _params) do
    conn
    |> authenticate
    |> render("welcome.html", name: get_session(conn, :user))
  end
end
