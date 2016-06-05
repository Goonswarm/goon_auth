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
  def handle_auth(conn, _) do
    text(conn, "Access granted.")
  end
end
