defmodule GoonAuth.PasswordChangeController do
  @moduledoc "Allow password changes for users in LDAP"
  use GoonAuth.Web, :controller
  require Logger
  alias GoonAuth.LDAP

  @doc "Render password change form page."
  def password_change_form(conn, _params) do
    render(conn, "pwchange.html")
  end

  @doc """
  Attempt to change a user's password.
  1. Validate that the new passwords match
  2. Attempt to bind to LDAP with the user's supplied credentials
  3. Use user-bound LDAP connection to modify password
  """
  def change_password_handler(conn, params) do
    # Extract form fields
    change = params["password"]
    name = change["name"]
    current = change["current"]
    password = change["password"]
    confirmation = change["password_confirm"]

    # Perform input verifications
    all_exist = Enum.all?([name, current, password, confirmation])
    passwords_match = password == confirmation
    long_password = String.length(password) >= 8

    if all_exist and passwords_match and long_password do
      change_password(conn, name, current, password)
    else
      conn
      |> error("Try to fill in the form correctly this time!")
    end
  end

  def change_password(conn, name, current, password) do
    Logger.info("Attempting to change password for #{name}")
    case LDAP.connect_user(name, current) do
      {:error, :invalid_credentials} -> error(conn, "Your credentials are wrong!")
      {:ok, ldap_conn} ->
        dn = LDAP.dn(name, :user)
        new_pass = password |> String.to_char_list
        :ok = :eldap.modify_password(ldap_conn, dn, new_pass)
        :eldap.close(ldap_conn)
        success(conn, name)
    end
  end

  def error(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: "/change-password")
  end

  def success(conn, name) do
    Logger.info("Changed password for #{name}")
    IO.inspect conn
    conn
    |> put_flash(:info, "#{name}, your password has been updated.")
    |> redirect(to: "/")
  end
end
