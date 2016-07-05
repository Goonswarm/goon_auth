defmodule GoonAuth.LDAP.User do
  @moduledoc """
  Schema and changesets for LDAP user objects.

  Transparently manages group and corporation membership as a member of the user
  structure.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias GoonAuth.LDAP.Utils

  @doc """
  A user LDAP object as represented by the organizationalPerson and goonPilot
  object classes.
  """
  @primary_key {:cn, :string, autogenerate: false}
  schema "users" do
    # Fields stored on the user object
    field :sn, :string
    field :password, :string
    field :mail, :string
    field :refreshToken, :string
    field :pilotActive, :string, default: "FALSE"

    # Fields stored on group objects but controlled by user struct
    field :corporation, :string
    field :groups, {:array, :string}, default: []
  end

  # Various changesets for different user operations

  # User registration involves several changesets as data is retrieved from
  # multiple sources (EVE API, registration form and computed values)

  @doc "Changeset for data from registration or password reset form"
  def user_form(user, params) do
    user
    |> cast(params, [:password, :mail])
    |> validate_confirmation(:password, required: true)
    |> validate_length(:password, min: 8)
  end

  @doc "Changeset for registration through information retrieved from EVE API"
  def registration_api(user, params) do
    user
    |> cast(params, [:cn, :sn, :refreshToken, :pilotActive])
    |> validate_required([:cn, :sn, :refreshToken])
    |> validate_pilot_status
  end

  @doc "Defines a changeset to be used when updating a user"
  def update(user, params \\ %{}) do
    user
    |> cast(params, [:mail, :refreshToken, :pilotActive, :corporation, :groups])
    |> validate_pilot_status
  end

  # Validates the pilot status field (pilotActive)
  defp validate_pilot_status(changeset) do
    changeset
    |> validate_inclusion(:pilotActive, ["TRUE", "FALSE", "EXPIRED", "BANNED"])
  end

  # Translation to and from LDAP operations
  @doc """
  Turns a user updating changeset into a list of LDAP modifications.
  LDAP modifications are returned as a list of tuples with the DN to be modified
  as the first and the modifications as the second element.
  """
  def to_modifications(changeset) do
    if changeset.valid? do
      modifications = changeset.changes
      |> Enum.map(&(to_modification(changeset.data, &1)))
      |> List.flatten
      # Group changes by DN and only pass on the changes
      |> Enum.group_by(fn({dn, _}) -> dn end, fn({_, mod}) -> mod end)
      {:ok, modifications}
    else
      {:error, changeset.errors}
    end
  end

  # Corporation changes are handled as eventually consistent:
  # If the user is not a member of any corporation and a corporation change is
  # received, the user will be added to the new corporation.
  #
  # If the user is a member of any corporation and a corporation change is
  # received, the user will be removed from their current corporation.
  # In case the user is just moving between authorised corporations they will be
  # added again in the next update.
  defp to_modification(user, {:corporation, value}) do
    user_dn = Utils.dn(user.cn, :user)

    cond do
      user.corporation ->
        # User is in a corporation - remove them!
        corp_dn = Utils.dn(user.corporation, :corp)
        {corp_dn, [:eldap.mod_delete('member', [user_dn])]}
      user.corporation == nil and value ->
        # User is not in a corporation, but one has been supplied - add them!
        corp_dn = Utils.dn(value, :corp)
        {corp_dn, [:eldap.mod_add('member', [user_dn])]}
    end
  end

  # Group modifications will cause changes in all groups that are added or removed.
  defp to_modification(user, {:groups, value}) do
    to_add = :lists.subtract(value, user.groups)
    to_remove = :lists.subtract(user.groups, value)
    user_dn = Utils.dn(user.cn, :user)

    add_changes = Enum.map(to_add, fn(group) ->
      group_dn = Utils.dn(group, :group)
      change = :eldap.mod_add('member', [user_dn])
      {group_dn, change}
    end)

    remove_changes = Enum.map(to_remove, fn(group) ->
      group_dn = Utils.dn(group, :group)
      change = :eldap.mod_delete('member', [user_dn])
      {group_dn, change}
    end)
    [add_changes, remove_changes]
  end

  # Other modifications occur directly on the user DN
  defp to_modification(user, {key, value}) do
    user_dn = Utils.dn(user.cn, :user)
    change = :eldap.mod_replace(Atom.to_charlist(key),
                                [String.to_charlist(value)])
    {user_dn, change}
  end

  @doc "Insert a user into LDAP"
  def insert(conn, user) do
    # Default object classes for all users
    objectClasses = ['organizationalPerson', 'goonPilot']

    dn = Utils.dn(user.cn, :user)
    entry = [
      {'objectClass', objectClasses},
      format_ldap('cn', user.cn),
      format_ldap('sn', user.sn),
      format_ldap('pilotActive', user.pilotActive),
      format_ldap('refreshToken', user.refreshToken),
      format_ldap('mail', user.mail),
    ]

    :ok = :eldap.add(conn, dn, entry)
    :ok = :eldap.modify_password(conn, dn, String.to_charlist(user.password))
  end

  defp format_ldap(name, attr) do
    {name, [String.to_charlist(attr)]}
  end

  @doc "Retrieves a user from LDAP"
  def retrieve(conn, username) do
    {:ok, user} = Utils.retrieve(conn, username, :user)
    {:ok, groups} = Utils.find_groups(conn, username, :group)
    {:ok, corp} = Utils.find_groups(conn, username, :corp)

    {:ok, %GoonAuth.LDAP.User{
        cn: user["cn"],
        sn: user["sn"],
        mail: user["mail"],
        refreshToken: user["refreshToken"],
        pilotActive: user["pilotActive"],
        groups: groups,
        corporation: List.first(corp),
    }}
  end
end
