defmodule WebAuthnLiveview.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      WebAuthnLiveviewWeb.Telemetry,
      # Start the Ecto repository
      WebAuthnLiveview.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: WebAuthnLiveview.PubSub},
      # Start Finch
      {Finch, name: WebAuthnLiveview.Finch},
      # Start the Endpoint (http/https)
      WebAuthnLiveviewWeb.Endpoint
      # Start a worker by calling: WebAuthnLiveview.Worker.start_link(arg)
      # {WebAuthnLiveview.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WebAuthnLiveview.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WebAuthnLiveviewWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
