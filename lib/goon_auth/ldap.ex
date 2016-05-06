defmodule GoonAuth.LDAP do
  @moduledoc "Module for all LDAP related functions"

  # Static LDAP values
  @basedn "dc=tendollarbond,dc=com"
  @userdn "ou=users,#{@basedn}"
  @corpdn "ou=corporations,#{@basedn}"

  @doc "Retrieve a user from LDAP"
  @spec get_user(binary()) :: {:ok, term} | :not_found
  def get_user(username) do
    {:ok, conn} = connect_admin
    search = [
      filter: :eldap.equalityMatch('cn', String.to_char_list(username)),
      base: String.to_char_list(@userdn),
      scope: :eldap.singleLevel
    ]
    {:ok, {:eldap_search_result, result, _ref}} = :eldap.search(conn, search)
    :eldap.close(conn)

    case result do
      [] -> :not_found
      [{:eldap_entry, _dn, user}] -> {:ok, :maps.from_list(user)}
    end
  end

  @doc "Prepare a user structure for insertion into LDAP"
  def prepare_user(usermap) do
    # Convert attributes into Erlang strings
    name  = usermap[:name]
    cn    = name                    |> String.to_char_list
    dn    = dn(name, :user)         |> String.to_char_list
    mail  = usermap[:email]         |> String.to_char_list
    token = usermap[:refresh_token] |> String.to_char_list

    corp  = usermap[:corporation]
          |> dn(:corp)
          |> String.to_char_list

    # Create a simple name that bad external services can use
    simple_name = name |> String.downcase |> String.replace(" ", "_")

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
    dn   = dn(user, :user) |> String.to_char_list
    pass = String.to_char_list(password)

    {:ok, conn} = connect

    case :eldap.simple_bind(conn, dn, pass) do
      {:error, :invalidCredentials} -> {:error, :invalid_credentials}
      :ok -> {:ok, conn}
    end
  end

  @doc "Changes a user's LDAP password"
  def change_password(user, current_pw, new_pw) do
    dn = dn(user, :user) |> String.to_char_list
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
    "cn=#{user},#{@userdn}"
  end
  def dn(corp, :corp) do
    "cn=#{corp},#{@corpdn}"
  end
end
