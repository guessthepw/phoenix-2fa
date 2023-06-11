defmodule Phoenix2FA.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Phoenix2FA.Repo

  alias Phoenix2FA.Accounts.{User, UserToken, UserNotifier}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs, validate_email: false)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_user_email(user, "valid password", %{email: ...})
      {:ok, %User{}}

      iex> apply_user_email(user, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  def apply_user_email(user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(user_email_multi(user, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp user_email_multi(user, email, context) do
    changeset =
      user
      |> User.email_changeset(%{email: email})
      |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, [context]))
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm_email/#{&1})")
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Updates the user password.

  ## Examples

      iex> update_user_password(user, "valid password", %{password: ...})
      {:ok, %User{}}

      iex> update_user_password(user, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.token_and_context_query(token, "session"))
    :ok
  end

  ## Confirmation

  @doc ~S"""
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &url(~p"/users/confirm/#{&1}"))
      {:error, :already_confirmed}

  """
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded_token))
    end
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, ["confirm"]))
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/users/reset_password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  alias Phoenix2FA.Accounts.UserKey

  @doc """
  Returns the list of user_keys.

  ## Examples

      iex> list_user_keys()
      [%UserKey{}, ...]

  """
  def list_user_keys do
    Repo.all(UserKey)
  end

  @doc """
  Gets a single user_key.

  Raises `Ecto.NoResultsError` if the User key does not exist.

  ## Examples

      iex> get_user_key!(123)
      %UserKey{}

      iex> get_user_key!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user_key!(id), do: Repo.get!(UserKey, id)

  @doc """
  Creates a user_key.

  ## Examples

      iex> create_user_key(%{field: value})
      {:ok, %UserKey{}}

      iex> create_user_key(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_user_key(attrs \\ %{}) do
    %UserKey{}
    |> UserKey.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user_key.

  ## Examples

      iex> update_user_key(user_key, %{field: new_value})
      {:ok, %UserKey{}}

      iex> update_user_key(user_key, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_key(%UserKey{} = user_key, attrs) do
    user_key
    |> UserKey.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user_key.

  ## Examples

      iex> delete_user_key(user_key)
      {:ok, %UserKey{}}

      iex> delete_user_key(user_key)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user_key(%UserKey{} = user_key) do
    Repo.delete(user_key)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user_key changes.

  ## Examples

      iex> change_user_key(user_key)
      %Ecto.Changeset{data: %UserKey{}}

  """
  def change_user_key(%UserKey{} = user_key, attrs \\ %{}) do
    UserKey.changeset(user_key, attrs)
  end

  @doc """
  List all u2f keys for a user
  """
  def list_u2f_keys_for_user(%{id: user_id}) do
    from(key in UserKey)
    |> where([key], key.user_id == ^user_id and key.kind == :u2f)
    |> Repo.all()
  end

  def list_u2f_keys_for_user(user_id) do
    from(key in UserKey)
    |> where([key], key.user_id == ^user_id and key.kind == :u2f)
    |> Repo.all()
  end

  @doc """
  List all totp_key keys for a user
  """
  def list_totp_key_keys_for_user(user_id) do
    from(key in UserKey)
    |> where([key], key.user_id == ^user_id and key.kind == :totp)
    |> Repo.all()
  end

  @doc """
  List all recovery keys for a user
  """
  def list_recovery_codes_for_user(user_id) do
    from(key in UserKey)
    |> where([key], key.user_id == ^user_id and key.kind == :recovery)
    |> Repo.all()
  end

  @doc """
  Check if a user has recovery codes already
  """
  def user_has_recovery_codes?(%{id: user_id}) do
    user_has_recovery_codes?(user_id)
  end

  def user_has_recovery_codes?(user_id) do
    list_recovery_codes_for_user(user_id) != []
  end

  @recovery_code_len 8
  @num_recovery_codes 10
  @doc """
  Generates a list of unique recovery codes to store for a user.

  ## Examples

    iex> generate_recovery_codes()
    ["31582325", "93159643", "10424484", "50731921", "56099500", "31542770",
    "53397924", "63373450", "44424523", "12871382"]
  """
  def generate_recovery_codes() do
    for _count <- 1..@num_recovery_codes do
      <<n::40>> = :crypto.strong_rand_bytes(5)

      n
      |> Integer.to_string()
      |> String.slice(0, @recovery_code_len)
      |> String.pad_leading(@recovery_code_len, "0")
    end
  end

  @doc """
  Returns the recovery code length
  """
  def get_recovery_code_length(), do: @recovery_code_len

  @doc """
  """

  def get_user_key_by_credential_id(credential_id) do
    from(key in UserKey)
    |> where([key], key.cred_id == ^credential_id)
    |> Repo.one()
  end

  @doc """
  List all user keys for a user
  """
  def list_user_keys_for_user(user_id) do
    from(key in UserKey)
    |> where([key], key.user_id == ^user_id)
    |> Repo.all()
  end

  @doc """
  Set up a TOTP secret for confirmation

  Takes the user struct of the user trying to register a new key and returns a map with
  two keys. secret and qr_code_uri.
  """

  def setup_totp_for_confirmation(current_user) do
    secret = NimbleTOTP.secret()

    qr_code_uri =
      NimbleTOTP.otpauth_uri("Phoenix2FA:#{current_user.email}", secret, issuer: "Phoenix2FA")

    %{secret: secret, qr_code_uri: qr_code_uri}
  end

  @doc """
  Set up a U2F secret for confirmation

  Takes the user struct of the user trying to register a new key and returns a map with
  two keys. challenge and cred_ids.
  """

  def setup_u2f_for_confirmation(current_user) do
    challenge = Wax.new_registration_challenge([])

    cred_ids =
      list_u2f_keys_for_user(current_user)
      |> Enum.map(& &1.cred_id)

    %{challenge: challenge, cred_ids: cred_ids}
  end

  @doc """
  Generate and save recovery codes for a user
  """

  def create_valid_recovery_codes(current_user) do
    generate_recovery_codes()
    |> Enum.reduce(Ecto.Multi.new(), fn recovery_code, multi ->
      user_key_attrs = %{
        user_id: current_user.id,
        mfa_key: recovery_code,
        last_used: DateTime.utc_now(),
        kind: :recovery,
        label: "Backup recovery codes",
        cred_id: recovery_code
      }

      changeset = UserKey.changeset(%UserKey{}, user_key_attrs)

      Ecto.Multi.insert(multi, recovery_code, changeset, [])
    end)
    |> Repo.transaction()
  end
end
