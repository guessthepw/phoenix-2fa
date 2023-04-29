defmodule WebAuthnLiveview.Repo do
  use Ecto.Repo,
    otp_app: :web_authn_liveview,
    adapter: Ecto.Adapters.Postgres
end
