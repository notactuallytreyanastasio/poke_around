defmodule PokeAround.AI.Supervisor do
  @moduledoc """
  Supervisor for AI-related processes.

  Currently supervises:
  - Tagger: continuous background tagging of links using Ollama
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      PokeAround.AI.Tagger
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
