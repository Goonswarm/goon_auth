defmodule GoonAuth.AuthController do
  @moduledoc """
  Support for arbitrary authentication requests through nginx's auth proxy
  functionality.
  """
  use GoonAuth.Web, :controller
  alias GoonAuth.LDAP
  import GoonAuth.LoginController, only: [logged_in?: 1]

  @doc """
  Performs an authentication check for active users.
  This is called by nginx for authenticating proxied requests.
  """
  def auth_check(conn, _params) do
    case logged_in?(conn) do
      {:error, :not_logged_in} ->
        conn
        |> put_status(401)
        |> text("Login required")
      {:ok, user} ->
        {:ok, ldap_conn} = LDAP.connect
        active? = LDAP.is_active?(ldap_conn, user)
        :eldap.close(ldap_conn)
        IO.inspect active?

        if active? do
          text(conn, "Access granted")
        else
          conn
          |> put_status(403)
          |> text("Inactive user")
        end
    end
  end
end
