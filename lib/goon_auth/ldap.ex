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

  # Static LDAP values
  @basedn "dc=tendollarbond,dc=com"
  @userdn "ou=users,#{@basedn}"
  @corpdn "ou=corporations,#{@basedn}"

  @doc "Prepare a user structure for insertion into LDAP"
  def prepare_user(usermap) do
    # Convert attributes into Erlang strings
    name  = usermap[:name]
    cn    = name                    |> String.to_char_list
    dn    = dn(name, :user)
    mail  = usermap[:email]         |> String.to_char_list
    token = usermap[:refresh_token] |> String.to_char_list

    simple_name = sanitize_name(name)

    corp  = usermap[:corporation] |> dn(:corp)

    objectClasses = ['organizationalPerson', 'goonPilot']

    entry = [
      {'objectClass', objectClasses},
      {'cn', [cn]},
      {'sn', [simple_name]}, # Yes, I know that sn stands for surname. :getout:
      {'mail', [mail]},
      {'refreshToken', [token]},
      {'corporation', [corp]}
    ]

    {:ok, dn, entry}
  end

  @doc "Adds a user to LDAP and sets its password"
  def register_user(usermap) do
    {:ok, dn, entry} = prepare_user(usermap)
    {:ok, conn} = connect_admin
    :ok = :eldap.add(conn, dn, entry)

    # Set password
    pass = usermap[:password] |> String.to_char_list
    :ok = :eldap.modify_password(conn, dn, pass)

    # Done!
    :eldap.close(conn)
  end

  @doc "Retrieves a user or corporation from LDAP"
  @spec retrieve(binary, :user | :corp) :: {:ok, term} | :not_found
  def retrieve(name, type) do
    {:ok, conn} = connect_admin
    # Searching for the base object on a distinguished name gives us
    # exactly that object, i.e. the user or corporation.
    search = [
      filter: :eldap.equalityMatch('objectClass', object_class(type)),
      base: dn(name, type),
      scope: :eldap.baseObject
    ]

    result = :eldap.search(conn, search)
    :eldap.close(conn)

    case result do
      {:error, :noSuchObject} -> :not_found
      {:ok, {:eldap_search_result, [], _ref}} -> :not_found
      {:ok, {:eldap_search_result, object_result, _ref}} ->
        [{:eldap_entry, _dn, object}] = object_result
        # eldap will return a Keymap which we can turn into a slightly nicer
        # structure using maps, however the values will still be Erlang strings.
        {:ok, :maps.from_list(object)}
    end
  end

  @doc "Connects to LDAP and returns socket"
  def connect do
    conf = Application.get_env(:goon_auth, :ldap)
    {:ok, conn} = :eldap.open([conf[:host]], [port: conf[:port]])
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

  @doc "Create distinguished names from common names"
  def dn(user, :user) do
    "cn=#{user},#{@userdn}" |> String.to_char_list
  end
  def dn(corp, :corp) do
    "o=#{corp},#{@corpdn}" |> String.to_char_list
  end

  @doc """
  Returns the object class to filter by for users / corporations. The reason for
  filtering based on this is that we do not want the auth system to be able to,
  for example, modify service user passwords.
  """
  def object_class(type) do
    case type do
      :user -> 'goonPilot'
      :corp -> 'organization'
    end
  end

  @doc "Sanitize usernames for use in bad external services"
  def sanitize_name(name) do
    name
    |> String.downcase
    |> String.replace(" ", "_")
    |> String.replace("'", "")
  end
end
