defmodule GoonAuth.KeyController do
  @moduledoc "Provides a way for users to upgrade their API keys"
  use GoonAuth.Web, :controller
  require Logger
  alias GoonAuth.EVE.Auth

  @doc "The OAuth equivalent of a full API key"
  def stasi_scopes do
    ["characterAccountRead", "characterAssetsRead", "characterBookmarksRead",
     "characterCalendarRead", "characterChatChannelsRead", "characterClonesRead",
     "characterContactsRead", "characterContactsWrite", "characterContractsRead",
     "characterFactionalWarfareRead", "characterFittingsRead",
     "characterFittingsWrite", "characterIndustryJobsRead", "characterKillsRead",
     "characterLocationRead", "characterLoyaltyPointsRead", "characterMailRead",
     "characterMarketOrdersRead", "characterMedalsRead",
     "characterNavigationWrite", "characterNotificationsRead",
     "characterOpportunitiesRead", "characterResearchRead", "characterSkillsRead",
     "characterStatsRead", "characterWalletRead", "corporationAssetRead",
     "corporationBookmarksRead", "corporationContractsRead",
     "corporationFactionalWarfareRead", "corporationIndustryJobsRead",
     "corporationKillsRead", "corporationMarketOrdersRead", "corporationMedalsRead",
     "corporationMembersRead", "corporationShareholdersRead",
     "corporationStructuresRead", "corporationWalletRead", "fleetRead",
     "fleetWrite", "publicData", "remoteClientUI"]
  end

  @doc "Renders a simple page explaining the upgrade process to the user"
  def key_upgrade_page(conn, _params) do
    oauth_url = Auth.authorize_url!(stasi_scopes())
    render(conn, "upgrade_key.html", oauth_url: oauth_url)
  end

  # fucking around with XML API
  def xml_get(token, access_type, uri, input \\ %{}) do
    url = "https://api.eveonline.com#{uri}"
    params = 
      Map.merge(input, %{accessToken: token.access_token, accessType: access_type})
    HTTPoison.get!(url, [], params: params)
  end
end
