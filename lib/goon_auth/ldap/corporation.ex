defmodule GoonAuth.LDAP.Corporation do
  use Ecto.Schema

  @doc """
  An EVE corporation as represented in LDAP. Basically the same as a group, but
  type-checked as DNs are generated in a different way.
  """
  @primary_key {:cn, :string, autogenerate: false}
  schema "corporations" do
    field :description, :string
    has_many :member, User
    has_many :owner, User
  end
end
