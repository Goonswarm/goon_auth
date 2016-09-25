defmodule GoonAuth.GroupView do
  use GoonAuth.Web, :view

  # If only a single owner / member is present on a group, the type of that
  # field changes - however we always expect a list. This normalises it.
  def listify_users(user_list) when is_list(user_list) do
    user_list
  end
  def listify_users(user) when is_binary(user) do
    [user]
  end
end
