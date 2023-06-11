defmodule Phoenix2FAWeb.UserKeyControllerTest do
  use Phoenix2FAWeb.ConnCase

  import Phoenix2FA.AccountsFixtures

  @create_attrs %{
    cred_id: "some cred_id",
    kind: :u2f,
    label: "some label",
    last_used: ~U[2023-06-09 14:32:00Z],
    mfa_key: "some mfa_key"
  }
  @update_attrs %{
    cred_id: "some updated cred_id",
    kind: :totp,
    label: "some updated label",
    last_used: ~U[2023-06-10 14:32:00Z],
    mfa_key: "some updated mfa_key"
  }
  @invalid_attrs %{cred_id: nil, kind: :totp, label: nil, last_used: nil, mfa_key: nil}

  describe "index" do
    setup [:log_user_in]

    test "lists all user_keys", %{conn: conn} do
      conn = get(conn, ~p"/users/user_keys")
      assert html_response(conn, 200) =~ "Listing User keys"
    end
  end

  describe "new user_key" do
    setup [:log_user_in]

    test "renders form", %{conn: conn} do
      conn = get(conn, ~p"/users/user_keys/new")
      assert html_response(conn, 200) =~ "New User key"
    end
  end

  describe "create user_key" do
    setup [:log_user_in]

    test "redirects to show when data is valid", %{conn: conn} do
      user = conn.assigns.current_user

      conn =
        post(conn, ~p"/users/user_keys/create",
          user_key: Map.put(@create_attrs, :user_id, user.id)
        )

      assert %{id: id} = redirected_params(conn)
      assert redirected_to(conn) == ~p"/users/user_keys/#{id}"

      conn = get(conn, ~p"/users/user_keys/#{id}")
      assert html_response(conn, 200) =~ "User key #{id}"
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/users/user_keys/create",
          user_key: @invalid_attrs,
          challenge: %{}
        )

      assert html_response(conn, 200) =~ "New User key"
    end
  end

  describe "edit user_key" do
    setup [:create_user_key, :log_user_in]

    test "renders form for editing chosen user_key", %{conn: conn, user_key: user_key} do
      conn = get(conn, ~p"/users/user_keys/#{user_key}/edit")
      assert html_response(conn, 200) =~ "Edit User key"
    end
  end

  describe "update user_key" do
    setup [:create_user_key, :log_user_in]

    test "redirects when data is valid", %{conn: conn, user_key: user_key} do
      conn = put(conn, ~p"/users/user_keys/#{user_key}", user_key: @update_attrs)

      assert redirected_to(conn) == ~p"/users/user_keys/#{user_key}"

      conn = get(conn, ~p"/users/user_keys/#{user_key}")
      assert html_response(conn, 200) =~ "some updated cred_id"
    end

    test "renders errors when data is invalid", %{conn: conn, user_key: user_key} do
      conn = put(conn, ~p"/users/user_keys/#{user_key}", user_key: @invalid_attrs)

      assert html_response(conn, 200) =~ "Edit User key"
    end
  end

  describe "delete user_key" do
    setup [:create_user_key, :log_user_in]

    test "deletes chosen user_key", %{conn: conn, user_key: user_key} do
      conn = delete(conn, ~p"/users/user_keys/#{user_key}")
      assert redirected_to(conn) == ~p"/users/user_keys"

      assert_error_sent 404, fn ->
        get(conn, ~p"/users/user_keys/#{user_key}")
      end
    end
  end

  defp create_user_key(_) do
    user_key = user_key_fixture()
    %{user_key: user_key}
  end

  defp log_user_in(%{conn: conn}) do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end
end
