defmodule GoonAuth.AuthController do
  @moduledoc """
  Support for arbitrary authentication requests through nginx's auth proxy
  functionality.
  """
  use GoonAuth.Web, :controller
  import GoonAuth.Auth, only: [authenticate: 2, authorize: 2]

  # Perform authentication and authorization for all requests proxied through
  # this controller. Do not redirect as nginx will take care of that.
  plug :authenticate, redirect: false
  plug :authorize, redirect: false

  # Simply respond with a successful status, if the connection gets this far the
  # authentication and authorization has already been performed.
  # The username is returned in a header which makes it available to nginx after
  # an authentication request is completed.
  def handle_auth(conn, _) do
    user = get_session(conn, :user)
    conn
    |> put_resp_header("X-Auth-User", user)
    |> text("Access granted")
  end
end
