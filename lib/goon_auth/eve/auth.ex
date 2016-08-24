defmodule GoonAuth.EVE.Auth do
  @moduledoc """
  OAuth authentication strategy for EVE SSO.

  This module is a straightforward implementation of a strategy for the OAuth2
  library. Please see the library documentation and EVE's SSO documentation if
  you need more information.
  """
  use OAuth2.Strategy

  def client do
    config = Application.get_env(:goon_auth, :crest)
    OAuth2.Client.new([
      strategy: __MODULE__,
      client_id: config[:client],
      client_secret: config[:secret],
      redirect_uri: config[:callback],
      site: "https://crest-tq.eveonline.com",
      authorize_url: "https://login.eveonline.com/oauth/authorize",
      token_url: "https://login.eveonline.com/oauth/token",
    ])
  end

  defp default_scopes do
    ["characterAccountRead", "characterKillsRead",
     "characterLocationRead","characterStatsRead",
     "characterSkillsRead", "publicData", "fleetRead"]
  end

  def authorize_url!(scopes \\ default_scopes(), params \\ []) do
    client()
    |> put_param(:scope, Enum.join(scopes, " "))
    |> OAuth2.Client.authorize_url!(params)
  end

  def get_token!(params \\ [], headers \\ [], options \\ []) do
    OAuth2.Client.get_token!(client(), params, headers, options)
  end

  # Strategy callbacks
  def authorize_url(oauth_client, params) do
    oauth_client
    |> OAuth2.Strategy.AuthCode.authorize_url(params)
  end

  def get_token(oauth_client, params, headers) do
    oauth_client
    |> put_header("Accept", "application/json")
    |> OAuth2.Strategy.AuthCode.get_token(params, headers)
  end

  # Other functions
  @doc """
  Retrieve a new access token based on the refresh token and check for potential
  error messages from the SSO service.
  """
  def refresh_token!(refresh_token) do
    token = OAuth2.AccessToken.new(%{"refresh_token" => refresh_token}, client())
    {:ok, refreshed} = OAuth2.AccessToken.refresh(token)

    # The library doesn't check the status codes, because why would you do that?
    error = refreshed.other_params["error"]

    if error do
      {:sso_error, error}
    else
      {:ok, refreshed}
    end
  end
end
