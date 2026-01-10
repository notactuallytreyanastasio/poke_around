defmodule PokeAround.ATProto.Supervisor do
  @moduledoc """
  Supervisor for ATProto-related processes.

  Manages:
  - TID generator agent
  - PDS sync worker
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # TID generator needs to run first
      PokeAround.ATProto.TID,
      # PDS sync worker
      PokeAround.ATProto.Sync
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
