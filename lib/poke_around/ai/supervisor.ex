defmodule PokeAround.AI.Supervisor do
  @moduledoc """
  Supervisor for AI-related processes.

  Supervises the Axon tagger for automatic link tagging.

  ## Configuration

      config :poke_around, PokeAround.AI.AxonTagger,
        enabled: true,
        model_path: "priv/models/tagger",
        threshold: 0.25,
        batch_size: 20,
        interval_ms: 10_000,
        langs: ["en"]
  """

  use Supervisor

  def start_link(opts \\ []) do
    name = opts[:name] || __MODULE__
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    config = Application.get_env(:poke_around, PokeAround.AI.AxonTagger, [])

    # Generate unique child name if supervisor has custom name
    tagger_name = case opts[:name] do
      nil -> PokeAround.AI.AxonTagger
      sup_name -> :"#{sup_name}_tagger"
    end

    children =
      if Keyword.get(config, :enabled, true) do
        [
          {PokeAround.AI.AxonTagger, [
            name: tagger_name,
            model_path: Keyword.get(config, :model_path, "priv/models/tagger"),
            threshold: Keyword.get(config, :threshold, 0.25),
            batch_size: Keyword.get(config, :batch_size, 20),
            interval: Keyword.get(config, :interval_ms, 10_000),
            langs: Keyword.get(config, :langs, ["en"]),
            auto_tag: Keyword.get(config, :auto_tag, true)
          ]}
        ]
      else
        []
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
