defmodule GoonAuth.Jabber do
  @moduledoc """
  Support for Jabber pings through TrumpBot.
  """

  # Convenience functions
  @doc "Sends a message to all online users"
  def message_online_users(message) do
    connected_users
    |> message_users(message)
  end

  # Specific RPC calls

  @doc "Returns all currently connected Jabber users."
  def connected_users do
    {:ok, response} = ejabberd_call("connected_users")
    response.param["connected_users"]
    |> Enum.map(fn(session) -> session["sessions"] end)
    |> Enum.map(fn(session) ->
      String.split(session, "/") |> List.first end)
    |> Enum.uniq
  end

  @doc "Sends a message to a user"
  def message_user(user, message) do
    params = %{
      type: "chat",
      from: "trumpbot@tendollarbond.com",
      to: user,
      subject: "",
      body: message
    }
    {:ok, _response} = ejabberd_call("send_message", params)
  end

  @doc "Sends a message to a group of users"
  def message_users(users, message) do
    Enum.map(users, fn(user) -> message_user(user, message) end)
  end

  # XMLRPC helper functions

  @doc """
  Sends an XMLRPC call to ejabberd.

  Authentication information is automatically added from application
  configuration.
  """
  def ejabberd_call(method_name, params \\ %{}) do
    config = Application.get_env(:goon_auth, :ejabberd, %{})
    request = %XMLRPC.MethodCall{
      method_name: method_name,
      params: [config, params]
    } |> XMLRPC.encode!

    headers = %{host: params["server"]}
    response = HTTPoison.post!("http://ejabberd-internal:5285/", request, headers)
    response.body |> XMLRPC.decode
  end
end
