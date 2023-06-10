defmodule Phoenix2FA.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Phoenix2FA.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Phoenix2FA.Accounts.register_user()

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  @doc """
  Generate a user_key.
  """
  def user_key_fixture(attrs \\ %{}) do
    user = user_fixture()

    {:ok, user_key} =
      attrs
      |> Enum.into(%{
        cred_id: "some cred_id",
        kind: :u2f,
        label: "some label",
        last_used: ~U[2023-04-28 14:19:00Z],
        mfa_key: "some mfa_key",
        user_id: user.id
      })
      |> Phoenix2FA.Accounts.create_user_key()

    user_key
  end
end
