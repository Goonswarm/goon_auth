defmodule GoonAuth.Utils do
  @moduledoc """
  Little helper functions that tie other parts of the software together.

  Currently includes some functions for integration between data stored in LDAP
  and EVE's CREST API.
  """
  alias GoonAuth.EVE.Auth
  alias GoonAuth.LDAP

  @doc """
  Retrieves a user's stored refresh token from LDAP and uses it to fetch a new
  authentication token from the EVE SSO.
  """
  def get_user_token(conn, username) do
    case LDAP.retrieve(conn, username, :user) do
      :not_found  -> :not_found
      {:ok, user} ->
        Auth.refresh_token!(user["refreshToken"])
    end
  end
end
