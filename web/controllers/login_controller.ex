defmodule GoonAuth.LoginController do
  use GoonAuth.Web, :controller
  require Logger
  alias GoonAuth.LDAP

  @doc "Renders login form if no active session is found"
  def login_form(conn, params) do
    case logged_in?(conn) do
      {:error, :not_logged_in} -> render(conn, "login.html")
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

  @doc "Validate user credentials against LDAP and creates the session"
  def check_login(conn, login) do
    username = login["name"]
    case LDAP.connect_user(username, login["password"]) do
      {:ok, ldap_conn} ->
        :eldap.close(ldap_conn)
        conn
        |> put_session(:user, username)
        |> put_flash(:info, "#{username}, you have now logged in.")
        |> redirect(to: get_target(conn))
      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "You entered invalid credentials, moron.")
        |> redirect(to: "/login")
    end
  end

  @doc "Returns the login redirect target if it exists"
  def get_target(conn) do
    case get_session(conn, :login_target) do
      nil    -> "/"
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
