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
  import GoonAuth.LDAP.Utils

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
end
