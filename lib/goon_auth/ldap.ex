defmodule GoonAuth.LDAP do
  @moduledoc "Module for all LDAP related functions"

  # Static LDAP values
  @basedn "dc=tendollarbond,dc=com"
  @userdn "ou=users,#{@basedn}"
  @corpdn "ou=corporations,#{@basedn}"

  @doc "Retrieve a user from LDAP"
  @spec get_user(binary()) :: {:ok, term} | :not_found
  def get_user(username) do
    {:ok, conn} = connect
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
    dn    = "cn=#{name},#{@userdn}" |> String.to_char_list
    mail  = usermap[:email]         |> String.to_char_list
    token = usermap[:refresh_token] |> String.to_char_list

    corp  = usermap[:corporation]
          |> fn(c) -> "cn=#{c},#{@corpdn}" end.()
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
    {:ok, conn} = connect
    :ok = :eldap.add(conn, dn, entry)

    # Set password
    pass = usermap[:password] |> String.to_char_list
    :ok = :eldap.modify_password(conn, dn, pass)

    # Done!
    :eldap.close(conn)
  end

  @doc "Connects and binds to LDAP with application configuration"
  def connect do
    conf = Application.get_env(:goon_auth, :ldap)
    pass = Application.get_env(:goon_auth, :ldap_password) |> String.to_char_list
    {:ok, conn} = :eldap.open([conf[:host]], [port: conf[:port]])
    :ok = :eldap.simple_bind(conn, conf[:admin_dn], pass)
    {:ok, conn}
  end
end
