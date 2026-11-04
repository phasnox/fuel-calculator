defmodule FuelCalculator.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FuelCalculatorWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:fuel_calculator, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FuelCalculator.PubSub},
      # Start a worker by calling: FuelCalculator.Worker.start_link(arg)
      # {FuelCalculator.Worker, arg},
      # Start to serve requests, typically the last entry
      FuelCalculatorWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FuelCalculator.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FuelCalculatorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
