defmodule GoonAuth.EVE.Auth do
  @moduledoc "OAuth authentication strategy for EVE SSO"
  use OAuth2.Strategy

  def client do
    config = Application.get_all_env(:goon_auth)
    OAuth2.Client.new([
      strategy: __MODULE__,
      client_id: config[:crest_client],
      client_secret: config[:crest_secret],
      redirect_uri: config[:crest_callback],
      site: "https://crest-tq.eveonline.com",
      authorize_url: "https://login.eveonline.com/oauth/authorize",
      token_url: "https://login.eveonline.com/oauth/token",
    ])
  end

  def authorize_url!(params \\ []) do
    scopes = ["characterAccountRead", "characterKillsRead",
              "characterLocationRead","characterStatsRead",
              "publicData"]
    client()
    |> put_param(:scope, Enum.join(scopes, " "))
    |> OAuth2.Client.authorize_url!(params)
  end

  def get_token!(params \\ [], headers \\ [], options \\ []) do
    OAuth2.Client.get_token!(client(), params, headers, options)
  end

  # Strategy callbacks
  def authorize_url(client, params) do
    OAuth2.Strategy.AuthCode.authorize_url(client, params)
  end

  def get_token(client, params, headers) do
    client
    |> put_header("Accept", "application/json")
    |> OAuth2.Strategy.AuthCode.get_token(params, headers)
  end
end
