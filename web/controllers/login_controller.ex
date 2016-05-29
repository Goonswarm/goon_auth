defmodule GoonAuth.LoginController do
  @moduledoc """
  This controller manages logins to GoonAuth for protected services, like pings.
  """
  use GoonAuth.Web, :controller
  require Logger
  alias GoonAuth.LDAP

  @doc "Renders login form if no active session is found"
  def login_form(conn, _params) do
    case logged_in?(conn) do
      {:error, :not_logged_in} ->
        render(conn, "login.html", target: get_target(conn))
      {:ok, user} ->
        conn
        |> put_flash(:info, "#{user}, you are already logged in!")
        |> redirect(to: "/")
    end
  end
  @doc "Receives a login request and logs the user in"
  def handle_login(conn, params) do
    case logged_in?(conn) do
      {:error, :not_logged_in} ->
        login = params["login"]
        check_login(conn, login)
      {:ok, user} ->
        conn
        |> put_flash(:info, "#{user}, you are already logged in!")
        |> redirect(to: "/")
    end
  end

  @doc "Destroys a users session"
  def handle_logout(conn, _params) do
    clear_session(conn)
    |> redirect(to: "/")
  end

  @doc "Validate user credentials against LDAP and creates the session"
  def check_login(conn, login) do
    username = login["name"]
    case LDAP.connect_user(username, login["password"]) do
      {:ok, ldap_conn} ->
        :eldap.close(ldap_conn)
        Logger.info("Logging in user #{username}")
        conn
        |> put_session(:user, username)
        |> put_resp_cookie("_goon_auth_user", username)
        |> put_flash(:info, "#{username}, you have now logged in.")
        |> redirect(to: login["target"])
      {:error, :invalid_credentials} ->
        Logger.info("Invalid login for user #{username}")
        conn
        |> put_flash(:error, "You entered invalid credentials, moron.")
        |> redirect(to: "/login")
    end
  end

  @doc """
  Returns the login redirect target if it exists.
  The session variable :login_target takes precedence over the X-Target header.
  If not target is found, we simply redirect to /
  """
  def get_target(conn) do
    case get_session(conn, :login_target) do
      nil ->
        case get_req_header(conn, "x-target") do
          []       -> "/"
          [target] -> target
        end
      target -> target
    end
  end

  @doc "Checks whether a user is currently logged in."
  def logged_in?(conn) do
    case get_session(conn, :user) do
      nil  -> {:error, :not_logged_in}
      user -> {:ok, user}
    end
  end
end
