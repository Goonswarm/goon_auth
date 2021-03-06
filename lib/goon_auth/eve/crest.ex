defmodule GoonAuth.EVE.CREST do
  @moduledoc """
  Convenience wrappers for using the CREST API.

  The functions in this module are intended to retrieve data from CREST and
  combine/enrich it with other information we need.
  """

  @doc "Retrieve ID of a character from the authentication token"
  def get_character_id(token) do
    decoded = get!(token, "/decode/")
    parse_id(decoded["character"]["href"])
  end

  @doc "Retrieve a character, including nested information such as the corporation"
  def get_character(token, character_id) do
    character = get!(token, "/characters/#{character_id}/")
    corporation = character["corporation"]["name"]
    character_id = character["id_str"]
    %{
      id: character_id,
      name: character["name"],
      corporation: corporation
    }
  end

  # Helper function to extract IDs from CREST URLs
  # Example: /corporations/1234567/ -> 1234567
  defp parse_id(url) do
    Regex.run(~r/([0-9]+)\//, url, capture: :all_but_first) |> hd
  end

  @doc "Helper function that fetches and decodes data from the API"
  # TODO: Check status and raise appropriate warning
  def get!(token, url) do
    import Poison
    # CCP API can be slow, lets use a longer timeout (15 seconds)
    response = OAuth2.AccessToken.get!(token, url, [], timeout: 15_000)
    response.body |> decode!
  end
end
