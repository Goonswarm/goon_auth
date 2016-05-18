defmodule GoonAuth.EVE.Sync do
  @moduledoc """
  A process that regularly syncs existing user's against the EVE API in order to
  check whether they are still eligible for access.

  This will also add applicants to the correct groups after updating their status.

  TODO: Find "leftover" users that may have pilotActive=FALSE but are still in a corp.
  """
  use GenServer
  require Logger
  alias GoonAuth.EVE.CREST
  alias GoonAuth.LDAP
  import GoonAuth.LDAP
  import GoonAuth.EVE.Auth, only: [refresh_token!: 1]

  # GenServer setup
  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(timer) do
    Logger.info("Starting EVE CREST sync process with #{timer} interval")
    interval = timer * 1000

    # Kick off timers shortly after starting server
    :erlang.send_after(3000, self(), :sync_inactive)
    :erlang.send_after(8000, self(), :sync_active)

    # Establish LDAP connection and monitor it so we can reconnect if it closes.
    # If it closes in the middle of a synchronisation the syncer will crash and
    # be restarted.
    {:ok, conn} = LDAP.connect_admin
    Process.monitor(conn)

    {:ok, %{interval: interval, conn: conn}}
  end

  # Handle reconnects
  def handle_info({:DOWN, _ref, :process, _pid, :closed}, state) do
    Logger.info("EVE CREST sync LDAP connection was closed, reconnecting...")
    {:ok, conn} = LDAP.connect_admin
    {:noreply, Map.put(state, :conn, conn)}
  end

  # Handle synchronisation timers
  def handle_info(:sync_active, state) do
    sync_users(state[:conn], self(), :active)
    :erlang.send_after(state[:interval], self(), :sync_active)
    {:noreply, state}
  end
  def handle_info(:sync_inactive, state) do
    sync_users(state[:conn], self(), :inactive)
    :erlang.send_after(state[:interval], self(), :sync_inactive)
    {:noreply, state}
  end

  # Handle synchronisation calls
  # The try/catch construct exists because dev/prod don't have matching
  # SSO keys, so when using the production LDAP in development there will
  # be SSO errors.
  def handle_cast({:sync, user_state, user}, state) do
    name = user[:user]["cn"]
    Logger.debug("Synchronising #{user_state} user #{name}")
    try do
      case user_state do
        :active   -> sync_active_user(state[:conn], user[:user], user[:corp])
        :inactive -> sync_inactive_user(state[:conn], user[:user])
      end
    rescue
      e -> Logger.error("Error synchronising #{name}: #{inspect e}")
    end
    {:noreply, state}
  end

  # Sync implementation

  @doc "Retrieves users from LDAP based on the pilotActive attribute value"
  def get_users_by_status(conn, status) do
    active =
      case status do
        :active -> 'TRUE'
        :inactive -> 'FALSE'
      end
    search = [
      filter: :eldap.equalityMatch('pilotActive', active),
      base: base_dn(:user),
      scope: :eldap.singleLevel
    ]

    {:ok, {:eldap_search_result, users, _ref}} = :eldap.search(conn, search)
    users = Enum.map(users, fn(entry) -> parse_object(entry) end)
    {:ok, users}
  end

  @doc """
  Synchronises active pilots and checks that they are still eligible.

  All active users are retrieved from LDAP, together with their corporations.
  A message is sent to the proces for every pilot to queue up the checks.
  """
  def sync_users(conn, server, status) do
    Logger.debug("Synchronising #{status} users ...")
    {:ok, users} = get_users_by_status(conn, status)

    users
    |> Enum.shuffle
    |> Enum.map(fn(user) ->
      Logger.debug("Queueing up check for user #{user["cn"]}")
      {:ok, corp} = LDAP.find_groups(conn, user["cn"], :corp)
      GenServer.cast(server, {:sync, status, %{user: user, corp: corp}})
    end)
  end

  @doc """
  Retrieves an active user from CREST and validates the corporation.

  If the corporation record is found not to match the result from CREST, the
  user will be deactivated and removed from the corporation in LDAP.

  If the user has moved to a different eligible corporation they will be
  reactivated on the next cycle.
  """
  def sync_active_user(conn, user, [corp]) do
    character = crest_fetch(user)

    # If the corporations don't match, deactivate the user and remove him from
    # corp.
    # If the user only changed his corporation, the account will be activated
    # again in the next cycle with the new corporation.
    if character[:corporation] != corp["cn"] do
      Logger.info("Deactivating #{user["cn"]} (CREST corp: #{character[:corporation]})")
      LDAP.remove_member(conn, corp["dn"], user["dn"])
      LDAP.set_user_status(conn, user["cn"], :inactive)
    end
  end

  @doc """
  Retrieves an inactive user from CREST and validates the corporation.

  If the user is found to be in an eligible corporation, their LDAP account is
  activated and they will be added to the appropriate LDAP group.
  """
  def sync_inactive_user(conn, user) do
    character = crest_fetch(user)

    result = LDAP.retrieve(character[:corporation], :corp)

    case result do
      # User still ineligible
      :not_found -> :ok
      # User became eligible
      {:ok, corp} ->
          Logger.info("Activating #{user["cn"]} (Corp: #{corp["cn"]})")
          LDAP.add_member(conn, corp["dn"], user["dn"])
          LDAP.set_user_status(conn, user["cn"], :active)
    end
  end

  # Helper function to fetch the character from CREST
  defp crest_fetch(user) do
    # Fetch character from CREST again
    {:ok, token} = refresh_token!(user["refreshToken"])
    character_id = CREST.get_character_id(token)
    CREST.get_character(token, character_id)
  end
end
