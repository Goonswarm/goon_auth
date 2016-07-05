defmodule GoonAuth.EVE.Sync do
  @moduledoc """
  A process that regularly syncs existing user's against the EVE API in order to
  check whether they are still eligible for access.

  This will also add applicants to the correct groups after updating their status.

  TODO: Find "leftover" users that may have pilotActive=FALSE but are still in a corp.
  """
  use GenServer
  require Logger
  alias GoonAuth.EVE.API
  alias GoonAuth.LDAP
  import GoonAuth.LDAP
  import GoonAuth.LDAP.Utils
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

  def sync_user(conn, user) do
    {:ok, token} = Auth.refresh_token(user.refreshToken)
    {:ok, character} = API.get_character(token)

    corporation = check_corp(conn, character[:corporation])
    changes = %{
      corporation: corporation,
      pilotActive: check_status(character),
    }
  end

  # Checks whether a corporation exists in LDAP and returns its name if so,
  # and nil otherwise.
  defp check_corp(conn, corp) do
    case LDAP.retrieve(conn, corp, :corp) do
      :not_found -> nil
      {:ok, _}   -> corp
    end
  end
end
