defmodule GoonAuth.EVE.XMLAPI do
  @moduledoc """
  Helper functions for accessing the EVE XML API. It can be accessed with the
  same tokens as CREST.
  """
  import SweetXml

  @doc """
  Get a resource from the XML API. Provided token should be a standard OAuth
  access token, access type should be set to "corporation" or "character"
  depending on the access type.

  Refer to XML API documentation for more information.
  """
  def xml_get(token, access_type, uri, input \\ %{}) do
    url = "https://api.eveonline.com#{uri}"
    params =
      Map.merge(input, %{accessToken: token.access_token, accessType: access_type})
    HTTPoison.get!(url, [], params: params)
  end

  @doc "Checks whether a player's EVE account subscription has expired."
  def account_expired?(token) do
    status = xml_get(token, "character", "/account/AccountStatus.xml.aspx").body
    IO.puts(status)
    paid_until = xpath(status, ~x"//result/paidUntil/text()"s)

    # Extract expiry date from the string
    <<year :: binary-size(4), "-",
    month :: binary-size(2), "-",
    day :: binary-size(2), _rest :: binary()>> = paid_until
    {:ok, expiry_date} = Date.new(String.to_integer(year),
                                  String.to_integer(month),
                                  String.to_integer(day))

    # Check if it has in fact expired.
    expired? = today > expiry_date
    {expiry_date, expired?}
  end

  def check(conn, username) do
    {:ok, token} = GoonAuth.Utils.get_user_token(conn, username)
    {expiry_date, expired} = account_expired?(token)
    res = %{user: username, expired: expired, expiry_date: expiry_date}
    if res[:expired] do
      IO.inspect(res, pretty: false)
    end
  end

  # Get current date ...
  def today do
    {today, _time} = :calendar.now_to_datetime(:erlang.timestamp)
    Date.from_erl!(today)
  end
  
  # Enum.map(names, &(Task.start(fn -> GoonAuth.EVE.XMLAPI.check(conn, &1) end)))
end
