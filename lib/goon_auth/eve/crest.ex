defmodule GoonAuth.EVE.CREST do
  @moduledoc "Convenience wrappers for using the CREST API"

  @doc "Retrieve ID of a character from the authentication token"
  def get_character_id(token) do
    decoded = get!(token, "/decode/")
    IO.inspect(decoded, pretty: true)
    parse_id(decoded["character"]["href"])
  end

  @doc "Retrieve a character, including nested information such as the corporation"
  def get_character(token, character_id) do
    character = get!(token, "/characters/#{character_id}/")
    corporation_id = character["corporation"]["id_str"]
    character_id = character["id_str"]
    # corporation = get_corporation(token, corporation_id)
    account_id = parse_id(character["accounts"]["href"])
    %{
      id: character_id,
      name: character["name"],
      corporation: corporation_id,
      account: account_id
    }
  end

  # TODO: CCP has not enabled this in CREST yet
  # @doc "Retrieve a corporation, including nested information such as the alliance"
  # def get_corporation(token, corp_id) do
  #   corporation = get!(token, "/corporations/#{corp_id}/")
  #   {:ok, corporation}
  # end

  # Helper function to extract IDs from CREST URLs
  defp parse_id(url) do
    Regex.run(~r/([0-9]+)\//, url, capture: :all_but_first) |> hd
  end

  @doc "Helper function that fetches and decodes data from the API"
  # TODO: Check status and raise appropriate warning
  def get!(token, url) do
    import Poison
    response = OAuth2.AccessToken.get!(token, url)
    response.body |> decode!
  end
end
