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
    user = get_session(conn, :user)
    {:ok, ldap_conn} = LDAP.connect
    {:ok, groups} = LDAP.find_groups(ldap_conn, user, :group)
    render(conn, "groups.html", groups: groups)
  end
end
