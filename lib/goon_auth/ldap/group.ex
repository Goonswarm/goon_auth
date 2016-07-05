defmodule GoonAuth.LDAP.Group do
  use Ecto.Schema

  @doc """
  An LDAP group as used for squad membership and service access control.
  """
  @primary_key {:cn, :string, autogenerate: false}
  schema "groups" do
    field :description, :string
    has_many :member, User
    has_many :owner, User
  end
end
