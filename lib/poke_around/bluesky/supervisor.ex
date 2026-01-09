defmodule PokeAround.Bluesky.Supervisor do
  @moduledoc """
  Supervisor for the Bluesky firehose subsystem.

  Manages the Turbostream WebSocket connection.

  ## Configuration

      config :poke_around, PokeAround.Bluesky.Supervisor,
        enabled: true

  Set `enabled: false` to disable the firehose on startup.
  """

  use Supervisor

  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(_opts) do
    if enabled?() do
      Logger.info("Starting Bluesky firehose supervisor")

      children = [
        PokeAround.Bluesky.Firehose,
        PokeAround.Links.Extractor
      ]

      Supervisor.init(children, strategy: :one_for_one)
    else
      Logger.info("Bluesky firehose disabled")
      :ignore
    end
  end

  @doc """
  Check if the firehose is enabled.
  """
  def enabled? do
    Application.get_env(:poke_around, __MODULE__, [])
    |> Keyword.get(:enabled, true)
  end
end
