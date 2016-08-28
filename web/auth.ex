defmodule GoonAuth.Auth do
  @moduledoc """
  A Plug to secure connections that require authentication.

  User sessions are checked and users are redirected to the login page if no
  session is found.
  """
  use Phoenix.Controller
  alias GoonAuth.LDAP
  import Plug.Conn
  require Logger

  @doc "Ensures that a user is logged in when accessing a page."
  def authenticate(conn, opts \\ [redirect: true]) do
    case get_session(conn, :user) do
      nil  ->
        conn
        |> put_flash(:info, "You must authenticate before accessing this page")
        |> put_session(:login_target, conn.request_path)
        |> respond_unauthenticated(opts[:redirect])
        |> halt
      _user -> conn
    end
  end

  @doc """
  Validates that a logged-in user has access to the resource.

  Checks whether the specified user is currently set as active in LDAP.

  Accepts a `:group` option that sets the LDAP group to check for. If no option
  is set, it will check the X-Access-Groups HTTP header which can be set by nginx
  for proxy-authentication requests.

  In addition a `:banned` option or `X-Banned-Groups` header can be set to
  disallow access specifically for members of a group.
  """
  def authorize(conn, opts) do
    user = get_session(conn, :user)
    {:ok, ldap_conn} = LDAP.connect

    # Ensure that pilotActive=true
    active? = LDAP.is_active?(ldap_conn, user)

    # Check group access restriction
    {:ok, groups} = LDAP.find_groups(ldap_conn, user, :group)
    access? = check_access(groups, conn, opts)

    :eldap.close(ldap_conn)

    if active? and access? do
      Logger.info("Granted access to #{conn.request_path} for user #{user}")
      conn
    else
      Logger.info("Denied access to #{conn.request_path} for user #{user}")
      conn
      |> respond_unauthorized(opts[:redirect])
      |> halt
    end
  end

  defp check_access(groups, conn, opts) do
    # Check whether the user is in the required access group
    has_access? =
      case required_groups(conn, opts) do
        []         -> true
        req_groups -> Enum.any?(groups, &(&1["cn"] in req_groups))
      end

    # Check whether the user is in any banned group
    not_banned? =
      case banned_groups(conn, opts) do
        []         -> true
        ban_groups -> Enum.all?(groups, &(not &1["cn"] in ban_groups))
      end

    has_access? and not_banned?
  end

  # Checks the :group option and X-Access-Groups header to figure out which
  # access groups are necessary.
  # Multiple groups in the HTTP header can be separated by commas.
  # If the user is in any of the groups, he will be granted access.
  defp required_groups(conn, opts) do
    case opts[:groups] do
      nil ->
        conn
        |> get_req_header("x-access-groups")
        |> Enum.flat_map(&(String.split(&1, ",")))
      groups -> groups
    end
  end

  # Checks the :banned option and X-Banned-Groups header to figure out if any
  # groups are banned from access.
  # Multiple groups in the HTTP header can be separated by commas.
  # If the user is in any of the groups, she will be denied access.
  defp banned_groups(conn, opts) do
    case opts[:banned] do
      nil ->
        conn
        |> get_req_header("x-banned-groups")
        |> Enum.flat_map(&(String.split(&1, ",")))
      groups -> groups
    end
  end

  # Redirects to login page if :redirect option is set to true, otherwise
  # returns 401.
  defp respond_unauthenticated(conn, redirect?) do
    case redirect? do
      # Treat nil like true (default should be to redirect if option is unset)
      nil   -> conn |> redirect(to: "/login")
      true  -> conn |> redirect(to: "/login")
      false -> conn |> put_status(401) |> text("Login required")
    end
  end

  # Responds with either a 403 status code and an "Access denied" message (for
  # use with nginx authentication proxying) or redirects the user to the landing
  # page and informs them that access was denied.
  defp respond_unauthorized(conn, redirect?) do
    case redirect? do
      # Treat nil value as true (same as above)
      nil   -> respond_unauthorized(conn, true)
      false -> conn |> put_status(403) |> text("Access denied.")
      true  ->
        conn
        |> put_flash(:error, "Access denied! :colbert:")
        |> redirect(to: "/")
    end
  end
end
