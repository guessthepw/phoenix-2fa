defmodule Phoenix2FA.Repo do
  use Ecto.Repo,
    otp_app: :phoenix_2fa,
    adapter: Ecto.Adapters.Postgres
end
