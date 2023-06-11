defmodule Phoenix2FAWeb.UserKeyController do
  @moduledoc """
  This controller manages user_key records in your database.
  """
  use Phoenix2FAWeb, :controller

  alias Phoenix2FAWeb.UserAuth
  alias Phoenix2FA.Accounts
  alias Phoenix2FA.Accounts.UserKey

  require Logger

  plug :_assign_unverified_user when action == :confirm

  @doc """
  Assigns the unverified user to the `:unverified_user` key in the connection.
  """
  def _assign_unverified_user(conn, _opts) do
    conn.private[:plug_session]["unverified_user_id"]
    |> Accounts.get_user!()
    |> case do
      nil -> conn
      user -> assign(conn, :unverified_user, user)
    end
  end

  @doc """
  Renders the index template with user_keys for the current_user
  """
  def index(conn, _params) do
    user_keys = Accounts.list_user_keys_for_user(conn.assigns.current_user.id)
    render(conn, :index, user_keys: user_keys)
  end

  @doc """
  Renders the show template with the given user_key
  """
  def show(conn, %{"id" => id}) do
    user_key = Accounts.get_user_key!(id)
    render(conn, :show, user_key: user_key)
  end

  @doc """
  Renders the edit template with the given user_key
  """
  def edit(conn, %{"id" => id}) do
    user_key = Accounts.get_user_key!(id)
    changeset = Accounts.change_user_key(user_key)
    render(conn, :edit, user_key: user_key, changeset: changeset)
  end

  @doc """
  Updates the given user_key with the given params, redirects to show or renders errors
  """
  def update(conn, %{"id" => id, "user_key" => user_key_params}) do
    user_key = Accounts.get_user_key!(id)

    case Accounts.update_user_key(user_key, user_key_params) do
      {:ok, user_key} ->
        conn
        |> put_flash(:info, "User key updated successfully.")
        |> redirect(to: ~p"/users/user_keys/#{user_key}")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit, user_key: user_key, changeset: changeset)
    end
  end

  @doc """
  Deletes the given user_key and redirects to index
  """
  def delete(conn, %{"id" => id}) do
    user_key = Accounts.get_user_key!(id)
    {:ok, _user_key} = Accounts.delete_user_key(user_key)

    conn
    |> put_flash(:info, "User key deleted successfully.")
    |> redirect(to: ~p"/users/user_keys")
  end

  @doc """
  Renders the new template for a new user_key
  """
  def new(conn, _params) do
    render(conn, :new, kind: nil)
  end

  @doc """
  Renders the new template for a new user_key
  """
  def create(conn, %{"kind" => "totp"}) do
    %{secret: secret, qr_code_uri: qr_code_uri} =
      Accounts.setup_totp_for_confirmation(conn.assigns.current_user)

    conn
    |> put_session(:totp_secret, secret)
    |> render(:new, qr_code_uri: qr_code_uri, kind: :totp)
  end

  def create(conn, %{"kind" => "u2f"} = _params) do
    changeset = Accounts.change_user_key(%UserKey{})

    %{challenge: challenge, cred_ids: cred_ids} =
      Accounts.setup_u2f_for_confirmation(conn.assigns.current_user)

    assigns = %{
      changeset: changeset,
      challenge: challenge,
      cred_ids: cred_ids,
      kind: :u2f
    }

    put_session(conn, :challenge, challenge)
    |> render(:new, assigns)
  end

  def create(conn, %{"kind" => "recovery"} = _params) do
    if Accounts.user_has_recovery_codes?(conn.assigns.current_user) do
      message =
        "Could not create Recovery Codes because they already exist. If you want to generate new ones please delete the existing ones."

      conn
      |> put_flash(:error, message)
      |> redirect(to: ~p"/users/user_keys", kind: :recovery)
    else
      Accounts.create_valid_recovery_codes(conn.assigns.current_user)
      |> case do
        {:ok, _} ->
          conn
          |> put_flash(:info, "Recovery codes generated.")
          |> redirect(to: ~p"/users/user_keys")

        _ ->
          conn
          |> put_flash(:error, "Could not create Recovery Codes, please try again.")
          |> redirect(to: ~p"/users/user_keys")
      end
    end
  end

  # manual
  def create(conn, %{"user_key" => user_key_params} = _params) do
    case Accounts.create_user_key(user_key_params) do
      {:ok, user_key} ->
        conn
        |> put_flash(:info, "User key created successfully.")
        |> redirect(to: ~p"/users/user_keys/#{user_key}")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset, kind: nil)
    end
  end

  @doc """
  Validates the given user_key.

  Creates a new user_key if valid or displays the error.
  """
  def validate(conn, %{"kind" => "totp", "one_time_code" => code, "label" => label}) do
    user = conn.assigns.current_user

    with(
      secret when secret != nil <- get_session(conn, :totp_secret),
      conn = delete_session(conn, :totp_secret),
      true <- NimbleTOTP.valid?(secret, code),
      user_key_params = %{
        user_id: user.id,
        mfa_key: secret,
        cred_id: code,
        label: label,
        last_used: NaiveDateTime.utc_now(),
        kind: :totp
      },
      {:ok, user_key} <- Accounts.create_user_key(user_key_params)
    ) do
      put_flash(conn, :info, "Key #{user_key.label} registered!")
    else
      false ->
        put_flash(conn, :error, "Invalid TOTP one time code.")

      {:error, _error} ->
        put_flash(conn, :error, "Label too long.")

      nil ->
        put_flash(conn, :error, "Timeout please retry.")
    end
    |> redirect(to: ~p"/users/user_keys")
  end

  def validate(conn, %{"cred_id_already_used" => "true"} = _params) do
    message =
      "Device already registered, please delete it and re-register if you would like to rename."

    put_flash(conn, :error, message)
  end

  def validate(conn, params) do
    current_user = conn.assigns.current_user
    challenge = conn.private[:plug_session]["challenge"]

    with(
      %{
        "attestationObject" => attestation_object_b64,
        "clientDataJSON" => client_data_json,
        "rawID" => raw_id_b64,
        "label" => label,
        "type" => "public-key"
      } <- params,
      attestation_object = Base.decode64!(attestation_object_b64),
      {:ok, {authenticator_data, _result}} <-
        Wax.register(attestation_object, client_data_json, challenge),
      mfa_key =
        :erlang.term_to_binary(authenticator_data.attested_credential_data.credential_public_key),
      user_key_params = %{
        user_id: current_user.id,
        mfa_key: mfa_key,
        cred_id: raw_id_b64,
        last_used: DateTime.utc_now(),
        kind: :u2f,
        label: label
      },
      {:ok, user_key} <- Accounts.create_user_key(user_key_params)
    ) do
      conn
      |> put_flash(:info, "Key registration success!")
      |> redirect(to: ~p"/users/user_keys/#{user_key}")
    else
      {:error, %Ecto.Changeset{errors: [label: {"can't be blank", [validation: :required]}]}} ->
        cred_ids =
          Accounts.list_u2f_keys_for_user(current_user)
          |> Enum.map(& &1.cred_id)

        put_flash(conn, :error, "Every user key needs a label")
        |> render(:new, challenge: challenge, cred_ids: cred_ids, kind: :u2f)

      {:error, resp} ->
        cred_ids =
          Accounts.list_u2f_keys_for_user(current_user)
          |> Enum.map(& &1.cred_id)

        message = Map.get(resp, :message, Map.get(resp, :reason))
        if message, do: Logger.error(message)

        conn
        |> put_flash(:error, "Key registration failed, please try again. - #{message}")
        |> render(:new, challenge: challenge, cred_ids: cred_ids, kind: :u2f)
    end
  end

  @doc """
  Confirms the given user_key.

  Is used when authenticating with a user_key.
  """
  def confirm(conn, %{"kind" => "recovery", "key" => key}) do
    Accounts.list_recovery_codes_for_user(conn.assigns.unverified_user.id)
    |> Enum.find(&(&1.cred_id == key))
    |> case do
      nil ->
        conn
        |> put_flash(:error, :invalid_key)
        |> redirect(to: ~p"/users/log_in")

      recover_code ->
        with {:ok, _} <- Accounts.delete_user_key(recover_code) do
          conn
          |> put_flash(:info, "Welcome back!")
          |> UserAuth.log_in_user(conn.assigns.unverified_user)
        else
          _ ->
            conn
            |> put_flash(:error, :try_again)
            |> redirect(to: ~p"/users/log_in")
        end
    end
  end

  def confirm(conn, %{"kind" => "totp", "key" => key}) do
    Accounts.list_totp_key_keys_for_user(conn.assigns.unverified_user.id)
    |> Enum.find(&NimbleTOTP.valid?(&1.mfa_key, key))
    |> case do
      nil ->
        conn
        |> put_flash(:error, :invalid_key)
        |> redirect(to: ~p"/users/log_in")

      totp_user_key ->
        with {:ok, _} <-
               Accounts.update_user_key(totp_user_key, %{last_used: DateTime.utc_now()}) do
          conn
          |> put_flash(:info, "Welcome back!")
          |> UserAuth.log_in_user(conn.assigns.unverified_user)
        else
          _ ->
            conn
            |> put_flash(:error, :try_again)
            |> redirect(to: ~p"/users/log_in")
        end
    end
  end

  def confirm(conn, %{
        "kind" => "u2f",
        "clientDataJSON" => client_data_json,
        "authenticatorData" => authenticator_data_b64,
        "sig" => sig_b64,
        "rawID" => raw_id_b64,
        "type" => "public-key"
      }) do
    authenticator_data = Base.decode64!(authenticator_data_b64)
    sig = Base.decode64!(sig_b64)
    user = conn.assigns.unverified_user
    challenge = get_session(conn, :authentication_challenge)

    case Wax.authenticate(raw_id_b64, authenticator_data, sig, client_data_json, challenge) do
      {:ok, _} ->
        Accounts.get_user_key_by_credential_id(raw_id_b64)
        |> Accounts.update_user_key(%{last_used: DateTime.utc_now()})

        conn
        |> put_flash(:info, "Welcome back!")
        |> UserAuth.log_in_user(user)

      {:error, _} = error ->
        Logger.info("Wax: authentication failed with error #{inspect(error)}")

        conn
        |> put_flash(:error, "Authentication failed.")
        |> redirect(to: "/")
    end
  end

  def confirm(conn, %{"kind" => "u2f"}) do
    user_id = conn.assigns.unverified_user.id

    existing_credential_list =
      Accounts.list_u2f_keys_for_user(user_id)
      |> Enum.map(fn %{mfa_key: cose_key, cred_id: cred_id} ->
        {cred_id, :erlang.binary_to_term(cose_key)}
      end)

    opts = [allow_credentials: existing_credential_list]

    assigns = %{
      challenge: Wax.new_authentication_challenge(opts),
      cred_ids: Enum.map(existing_credential_list, &elem(&1, 0)),
      user_id: user_id,
      kind: :u2f
    }

    conn
    |> put_session(:authentication_challenge, assigns.challenge)
    |> render(:confirm_key, assigns)
  end

  def confirm(conn, %{"kind" => kind}) do
    user_id = conn.assigns.unverified_user.id

    render(conn, :confirm_key, user_id: user_id, kind: kind |> String.to_atom())
  end

  def confirm(conn, _params) do
    render(conn, :confirm, user_id: conn.assigns.unverified_user.id)
  end
end
