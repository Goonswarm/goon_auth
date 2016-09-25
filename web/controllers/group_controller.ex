defmodule GoonAuth.GroupController do
  @moduledoc """
  Simple pages to support basic LDAP group management.
  """
  use GoonAuth.Web, :controller
  alias GoonAuth.LDAP
  import GoonAuth.Auth, only: [authenticate: 2]

  # All requests to this controller must be authenticated
  plug :authenticate

  def group_list(conn, _params) do
    user                  = get_session(conn, :user)
    {:ok, ldap_conn}      = LDAP.connect
    {:ok, groups}         = LDAP.find_groups(ldap_conn, user, :group)
    {:ok, managed_groups} = LDAP.find_groups(ldap_conn, user, :group, 'owner')
    render(conn, "groups.html", groups: groups, managed_groups: managed_groups)
  end

  def group_view(conn, %{"name" => name}) do
    user = get_session(conn, :user)
    {:ok, ldap_conn} = LDAP.connect
    {:ok, group} = LDAP.retrieve(ldap_conn, name, :group)
    render(conn, "group.html", group: group)
  end
end
