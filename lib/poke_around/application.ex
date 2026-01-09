defmodule PokeAround.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PokeAroundWeb.Telemetry,
      PokeAround.Repo,
      {DNSCluster, query: Application.get_env(:poke_around, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PokeAround.PubSub},
      # Bluesky firehose
      PokeAround.Bluesky.Supervisor,
      # AI tagging (runs independently)
      PokeAround.AI.Tagger,
      # Start to serve requests, typically the last entry
      PokeAroundWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PokeAround.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PokeAroundWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
