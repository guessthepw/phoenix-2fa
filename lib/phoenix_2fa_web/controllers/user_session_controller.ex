defmodule Phoenix2FAWeb.UserSessionController do
  use Phoenix2FAWeb, :controller

  alias Phoenix2FA.Accounts
  alias Phoenix2FAWeb.UserAuth

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Account created successfully!")
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    create(conn, params, "Password updated successfully!")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    with %{id: user_id} = user <- Accounts.get_user_by_email_and_password(email, password),
         [] <- Accounts.list_user_keys_for_user(user_id) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      nil ->
        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:error, "Invalid email or password")
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/users/log_in")

      [%{user_id: user_id} | _] ->
        conn
        |> put_session(:unverified_user_id, user_id)
        |> redirect(to: ~p"/users/user_keys/confirm")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
