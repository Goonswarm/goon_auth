defmodule GoonAuth.PingController do
  @moduledoc """
  Controller for sending Jabber pings.

  This will let users send Jabber pings to all currently logged in users.
  Sending pings is restricted to users in the LDAP group 'ping'.
  """
  use GoonAuth.Web, :controller
  import GoonAuth.LoginController, only: [logged_in?: 1]
  require Logger
  alias GoonAuth.Jabber
  alias GoonAuth.LDAP

  def ping_form(conn, _params) do
    case logged_in?(conn) do
      {:error, :not_logged_in} ->
        conn
        |> put_session(:login_target, "/ping")
        |> redirect(to: "/login")
      {:ok, user} ->
        render(conn, "ping.html")
    end
  end

  def handle_ping(conn, params) do
    # I'm too tired to not repeat myself, wtf
    case logged_in?(conn) do
      {:error, :not_logged_in} ->
        conn
        |> put_session(:login_target, "/ping")
        |> redirect(to: "/login")
      {:ok, user} ->
        send_ping(conn, user, params["ping"])
    end
  end

  def send_ping(conn, user, ping) do
    # Check LDAP permissions
    {:ok, ldap_conn} = LDAP.connect_admin
    {:ok, groups} = LDAP.find_groups(ldap_conn, user, :group)
    :eldap.close(ldap_conn)

    can_ping? = Enum.any?(groups, &(&1["cn"] == "pings"))

    if can_ping? do
      Logger.info("#{user} pinging all online Jabber users")
      Jabber.message_online_users(ping["ping"])
      conn
      |> put_flash(:info, "Ping sent to Jabber")
      |> redirect(to: "/ping")
    else
      conn
      |> put_flash(:error, "You're not allowed to send pings")
      |> redirect(to: "/login")
    end
  end
end
