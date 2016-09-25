defmodule GoonAuth.GroupController do
  @moduledoc """
  Simple pages to support basic LDAP group management.
  """
  alias GoonAuth.LDAP
  import GoonAuth.Auth, only: [authenticate: 2]
  require Logger
  use GoonAuth.Web, :controller

  # All requests to this controller must be authenticated
  plug :authenticate

  @doc """
  Fetches all groups that a user belongs to, as well as all groups that a user
  has permission to manage and displays them.
  """
  def group_list(conn, _params) do
    user                  = get_session(conn, :user)
    {:ok, ldap_conn}      = LDAP.connect
    {:ok, groups}         = LDAP.find_groups(ldap_conn, user, :group)
    {:ok, managed_groups} = LDAP.find_groups(ldap_conn, user, :group, 'owner')

    render(conn, "groups.html",
      groups: groups,
      managed_groups: managed_groups)
  end

  @doc """
  Shows detailed information about a group and provides the ability to
  add/remove group members.
  Only group managers can open this page.
  """
  def group_view(conn, %{"name" => name}) do
    user = get_session(conn, :user)
    {:ok, ldap_conn} = LDAP.connect
    {:ok, group} = LDAP.retrieve(ldap_conn, name, :group)

    if has_access?(group["owner"], user) do
      render(conn, "group.html", group: group)
    else
      Logger.warn("User #{user} attempted to view group #{name}!")
      conn
      |> put_flash(:error, "You don't have permission to manage this group!")
      |> redirect(to: "/groups")
    end
  end

  defp has_access?(group_owners, user) when is_list(group_owners) do
    dn_fragment = "cn=#{user},"
    Enum.any?(group_owners, fn(owner) ->
      String.contains?(owner, dn_fragment)
    end)
  end
  defp has_access?(owner, user) when is_binary(owner) do
    dn_fragment = "cn=#{user},"
    String.contains?(owner, dn_fragment)
  end
end
