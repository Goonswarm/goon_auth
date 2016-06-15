defmodule GoonAuth.LDAP do
  @moduledoc """
  Module for all LDAP related functions.

  Connections to LDAP can be established using either `connect_admin/0`, which
  will establish a connection and bind with the account specified in the Auth
  configuration, or `connect_user/2` which takes a username and password.

  Two convenience functions exist for handling LDAP structures:

  * `dn(name :: binary, :user | :corp)` - Creating full DNs from common names
  * `object_class(:user | :corp)` - Look up the object classes we expect for
    actual EVE objects.
  """

  @doc "Prepare a user structure for insertion into LDAP"
  def prepare_user(usermap) do
    # Convert attributes into Erlang strings
    name  = usermap[:name]
    cn    = name                    |> String.to_char_list
    dn    = dn(name, :user)
    mail  = usermap[:email]         |> String.to_char_list
    token = usermap[:refresh_token] |> String.to_char_list

    simple_name = sanitize_name(name)

    objectClasses = ['organizationalPerson', 'goonPilot']

    entry = [
      {'objectClass', objectClasses},
      {'cn', [cn]},
      {'sn', [simple_name]}, # Yes, I know that sn stands for surname. :getout:
      {'mail', [mail]},
      {'refreshToken', [token]},
      {'pilotActive', [usermap[:pilotActive]]},
    ]

    {:ok, dn, entry}
  end

  @doc """
  Adds a user to LDAP.

  This function will take the combined output of CREST and the registration
  form and add the user to LDAP.

  It will set the users corporation as a group.
  """
  def register_user(usermap) do
    # Prepare data
    {:ok, dn, entry} = prepare_user(usermap)
    pass = usermap[:password] |> String.to_char_list

    # Begin LDAP operations by adding user and setting password
    {:ok, conn} = connect_admin
    :ok = :eldap.add(conn, dn, entry)
    :ok = :eldap.modify_password(conn, dn, pass)

    # Add to corporation if one is set
    if usermap[:corporation] do
      corp_dn = usermap[:corporation] |> dn(:corp)
      add_member(conn, corp_dn, dn)
    end

    # Add to other group if set.
    if usermap[:group] do
      group_dn = usermap[:group] |> dn(:group)
      add_member(conn, group_dn, dn)
    end

    # Done!
    :eldap.close(conn)
  end

  @doc "Retrieves a user, corporation or group from LDAP"
  @spec retrieve(pid, binary, :user | :corp | :group) :: {:ok, term} | :not_found
  def retrieve(conn, name, type) do
    # Searching for the base object on a distinguished name gives us
    # exactly that object, i.e. the user or corporation.
    search = [
      filter: :eldap.equalityMatch('objectClass', object_class(type)),
      base: dn(name, type),
      scope: :eldap.baseObject
    ]

    result = :eldap.search(conn, search)

    case result do
      {:error, :noSuchObject} -> :not_found
      {:ok, {:eldap_search_result, [], _ref}} -> :not_found
      {:ok, {:eldap_search_result, entry, _ref}} ->
        {:ok, parse_object(List.first(entry))}
    end
  end

  @doc "Simply checks whether a given pilot name is an active user"
  def is_active?(conn, name) do
    {:ok, user} = retrieve(conn, name, :user)
    user["pilotActive"] == "true"
  end

  @doc "Finds the groups or corporations a user is a member of"
  def find_groups(conn, username, type) do
    user_dn = dn(username, :user)
    search = [
      filter: :eldap.extensibleMatch(user_dn, [type: 'member',
                                               matchingRule: 'distinguishedNameMatch']),
      base: base_dn(type),
      scope: :eldap.singleLevel,
      attributes: ['cn', 'description']
    ]

    result = :eldap.search(conn, search)
    case result do
      {:ok, {:eldap_search_result, groups, _ref}} ->
        groups = Enum.map(groups, &(parse_object &1))
        {:ok, groups}
    end
  end

  @doc "Connects to LDAP and returns socket"
  def connect do
    conf = Application.get_env(:goon_auth, :ldap)
    :eldap.open([conf[:host]], [port: conf[:port]])
  end

  @doc "Connects to LDAP and binds with administrator credentials"
  def connect_admin do
    {:ok, conn} = connect
    conf = Application.get_env(:goon_auth, :ldap)
    pass = Application.get_env(:goon_auth, :ldap_password) |> String.to_char_list
    :ok = :eldap.simple_bind(conn, conf[:admin_dn], pass)
    {:ok, conn}
  end

  @doc "Connects to LDAP and binds with user credentials"
  def connect_user(user, password) do
    dn   = dn(user, :user)
    pass = String.to_char_list(password)

    {:ok, conn} = connect

    case :eldap.simple_bind(conn, dn, pass) do
      {:error, :invalidCredentials} -> {:error, :invalid_credentials}
      :ok -> {:ok, conn}
    end
  end

  @doc """
  Changes a user's LDAP password.

  An LDAP connection is established using the user's own current password. LDAP
  needs to be configured to allow people to change their own passwords.
  """
  def change_password(user, current_pw, new_pw) do
    dn = dn(user, :user)
    new_pw = String.to_char_list(new_pw)

    case connect_user(user, current_pw) do
      {:error, err} -> {:error, err}
      {:ok, conn} ->
        :ok = :eldap.modify_password(conn, dn, new_pw)
        :ok = :eldap.close(conn)
    end
  end

  @doc "Updates a user status in LDAP"
  def set_user_status(conn, user, status) do
    status =
      case status do
        :active   -> 'true'
        :inactive -> 'false'
      end
    mod = :eldap.mod_replace('pilotActive', [status])
    :ok = :eldap.modify(conn, dn(user, :user), [mod])
  end

  @doc """
  Adds a user to an LDAP group or corporation by adding a new member entry with
  the users distinguished name.
  """
  def add_member(conn, group_dn, user_dn) do
    entry = :eldap.mod_add('member', [user_dn])
    :ok = :eldap.modify(conn, group_dn, [entry])
  end

  @doc "Removes a member from an LDAP group or corporation"
  def remove_member(conn, group_dn, user_dn) do
    entry = :eldap.mod_delete('member', [user_dn])
    :ok = :eldap.modify(conn, group_dn, [entry])
  end

  @doc "Create distinguished names from common names"
  def dn(name, type) do
    "cn=#{name},#{base_dn(type)}" |> String.to_char_list
  end

  @doc "Returns the base DN for the specified object type"
  def base_dn(type) do
    case type do
      :base  -> "dc=tendollarbond,dc=com"
      :user  -> "ou=users,dc=tendollarbond,dc=com"
      :group -> "ou=groups,dc=tendollarbond,dc=com"
      :corp  -> "ou=corporations,ou=groups,dc=tendollarbond,dc=com"
    end
  end

  @doc """
  Returns the object class to filter by for users / corporations. The reason for
  filtering based on this is that we do not want the auth system to be able to,
  for example, modify service user passwords.
  """
  def object_class(type) do
    case type do
      :user  -> 'goonPilot'
      :corp  -> 'groupOfNames'
      :group -> 'groupOfNames'
    end
  end

  @doc "Sanitize usernames for use in bad external services"
  def sanitize_name(name) do
    name
    |> String.downcase
    |> String.replace(" ", "_")
    |> String.replace("'", "")
  end

  @doc """
  Transforms LDAP attributes into easier to handle Elixir values.

  * Empty list (no attribute value) turns into nil
  * Single item list turns into binary
  * Multi-item list turns into binary list
  * Single item booleans are turned into real booleans
  """
  def get_attr(key, attr) do
    value =
      case attr do
        []             -> nil
        ['TRUE' | []]  -> true
        ['FALSE' | []] -> false
        [val | []]     -> List.to_string(val)
        _ -> Enum.map(attr, &(List.to_string &1))
      end
    {List.to_string(key), value}
  end

  @doc """
  Transforms a whole eldap entry into a sane Elixir format using get_attr/2.
  The result is a normal Elixir/Erlang map with binary keys and values.
  """
  def parse_object({:eldap_entry, dn, object}) do
    Enum.map(object, fn({k, v}) -> get_attr(k, v) end)
    |> :maps.from_list
    |> Map.put("dn", dn)
  end
end
