defmodule GoonAuth.LDAP.Utils do
  @moduledoc """
  Helper functions for use with all LDAP modules.
  """

  @doc "Create distinguished names from common names"
  def dn(name, type) do
    "cn=#{name},#{base_dn(type)}" |> String.to_char_list
  end

  @doc "Returns the base DN for the specified object type"
  def base_dn(type) do
    case type do
      :base  -> "dc=tendollarbond,dc=com"
      :user  -> "ou=users,dc=tendollarbond,dc=com"
      :group -> "ou=groups,dc=tendollarbond,dc=com"
      :corp  -> "ou=corporations,ou=groups,dc=tendollarbond,dc=com"
    end
  end

  @doc """
  Returns the object class to filter by for users / corporations. The reason for
  filtering based on this is that we do not want the auth system to be able to,
  for example, modify service user passwords.
  """
  def object_class(type) do
    case type do
      :user  -> 'goonPilot'
      :corp  -> 'groupOfNames'
      :group -> 'groupOfNames'
    end
  end

  @doc """
  Executes a list of LDAP modifications that are grouped in tuples of {DN, Mods}
  """
  def modify(conn, modifications) do
    Enum.each(modifications, fn({dn, mods}) ->
      :ok = :eldap.modify(conn, dn, mods)
    end)
  end

  @doc "Retrieves a user, corporation or group from LDAP"
  @spec retrieve(pid, binary, :user | :corp | :group) :: {:ok, term} | :not_found
  def retrieve(conn, name, type) do
    # Searching for the base object on a distinguished name gives us
    # exactly that object, i.e. the user or corporation.
    search = [
      filter: :eldap.equalityMatch('objectClass', object_class(type)),
      base: dn(name, type),
      scope: :eldap.baseObject
    ]

    result = :eldap.search(conn, search)

    case result do
      {:error, :noSuchObject} -> :not_found
      {:ok, {:eldap_search_result, [], _ref}} -> :not_found
      {:ok, {:eldap_search_result, entry, _ref}} ->
        {:ok, parse_object(List.first(entry))}
    end
  end

  @doc "Finds the groups or corporations a user is a member of"
  def find_groups(conn, username, type) do
    user_dn = dn(username, :user)
    search = [
      filter: :eldap.extensibleMatch(user_dn, [type: 'member',
                                               matchingRule: 'distinguishedNameMatch']),
      base: base_dn(type),
      scope: :eldap.singleLevel,
      attributes: ['cn', 'description']
    ]

    result = :eldap.search(conn, search)
    case result do
      {:ok, {:eldap_search_result, groups, _ref}} ->
        groups = Enum.map(groups, &(parse_object &1)["cn"])
        {:ok, groups}
    end
  end


  @doc """
  Transforms LDAP attributes into easier to handle Elixir values.

  * Empty list (no attribute value) turns into nil
  * Single item list turns into binary
  * Multi-item list turns into binary list
  * Single item booleans are turned into real booleans
  """
  def get_attr(key, attr) do
    value =
      case attr do
        []             -> nil
        ['TRUE' | []]  -> true
        ['FALSE' | []] -> false
        [val | []]     -> List.to_string(val)
        _ -> Enum.map(attr, &(List.to_string &1))
      end
    {List.to_string(key), value}
  end

  @doc """
  Transforms a whole eldap entry into a sane Elixir format using get_attr/2.
  The result is a normal Elixir/Erlang map with binary keys and values.
  """
  def parse_object({:eldap_entry, dn, object}) do
    Enum.map(object, fn({k, v}) -> get_attr(k, v) end)
    |> :maps.from_list
    |> Map.put("dn", dn)
  end
end
