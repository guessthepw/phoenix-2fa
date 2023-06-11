defmodule Phoenix2FA.Accounts.UserKey do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_keys" do
    field :cred_id, :string
    field :kind, Ecto.Enum, values: [:u2f, :totp, :recovery]
    field :label, :string
    field :last_used, :utc_datetime
    field :mfa_key, :binary
    field :user_id, :id

    timestamps()
  end

  @doc false
  def changeset(user_key, attrs) do
    user_key
    |> cast(attrs, [:cred_id, :label, :last_used, :mfa_key, :kind, :user_id])
    |> validate_required([:cred_id, :label, :last_used, :mfa_key, :kind, :user_id])
  end
end
