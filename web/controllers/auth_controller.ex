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
  def handle_auth(conn, _params) do
    case logged_in?(conn) do
      {:error, :not_logged_in} ->
        conn
        |> put_status(401)
        |> text("Login required")
      {:ok, user} ->
        check_access(conn, user)
    end
  end

  @doc """
  Performs access checks based on the incoming authentication request.
  Only active pilots are allowed. Nginx can optionally request users to be a
  member of a particular LDAP group by setting the X-Access-Group header.
  """
  def check_access(conn, user) do
    {:ok, ldap_conn} = LDAP.connect
    # Ensure that pilotActive=true
    active? = LDAP.is_active?(ldap_conn, user)

    # Check user's access group
    group_header = get_req_header(conn, "x-access-group")
    access? = check_user_groups(ldap_conn, user, group_header)

    :eldap.close(ldap_conn)

    if active? and access? do
      text(conn, "Access granted")
    else
      conn
      |> put_status(403)
      |> text("Inactive user")
    end
  end

  @doc "Check whether the user is in the correct group in LDAP"
  def check_user_groups(_, _, []) do
    true
  end
  def check_user_groups(ldap_conn, user, [group]) do
    {:ok, groups} = LDAP.find_groups(ldap_conn, user, :group)
    Enum.any?(groups, &(&1["cn"] == group))
  end
end
