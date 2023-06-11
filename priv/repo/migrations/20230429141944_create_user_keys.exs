defmodule Phoenix2FA.Repo.Migrations.CreateUserKeys do
  use Ecto.Migration

  def change do
    create table(:user_keys) do
      add :cred_id, :string
      add :label, :string
      add :last_used, :utc_datetime
      add :mfa_key, :binary
      add :kind, :string
      add :user_id, references(:users, on_delete: :nothing)

      timestamps()
    end

    create index(:user_keys, [:user_id])
  end
end
