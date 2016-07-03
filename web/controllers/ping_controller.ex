defmodule GoonAuth.PingController do
  @moduledoc """
  Controller for sending Jabber pings.

  This will let users send Jabber pings to all currently logged in users.
  Sending pings is restricted to users in the LDAP group 'ping'.
  """
  use GoonAuth.Web, :controller
  import GoonAuth.Auth, only: [authenticate: 2, authorize: 2]
  require Logger
  alias GoonAuth.Jabber

  plug :authenticate
  plug :authorize, banned: "no-pings"

  def ping_form(conn, _params) do
    render(conn, "ping.html")
  end

  def handle_ping(conn, params) do
    user = get_session(conn, :user)
    ping = params["ping"]

    message = """
    #{ping["ping"]}
    (pinged by #{user})
    """

    Logger.info("#{user} pinging all online Jabber users")
    Jabber.message_online_users(message)

    conn
    |> put_flash(:info, "Ping sent to Jabber")
    |> redirect(to: "/ping")
  end
end
