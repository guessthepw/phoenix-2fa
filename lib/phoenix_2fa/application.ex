defmodule Phoenix2FA.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      Phoenix2FAWeb.Telemetry,
      # Start the Ecto repository
      Phoenix2FA.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Phoenix2FA.PubSub},
      # Start Finch
      {Finch, name: Phoenix2FA.Finch},
      # Start the Endpoint (http/https)
      Phoenix2FAWeb.Endpoint
      # Start a worker by calling: Phoenix2FA.Worker.start_link(arg)
      # {Phoenix2FA.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Phoenix2FA.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Phoenix2FAWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
