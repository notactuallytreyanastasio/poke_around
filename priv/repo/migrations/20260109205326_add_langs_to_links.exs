defmodule PokeAround.Repo.Migrations.AddLangsToLinks do
  use Ecto.Migration

  def change do
    alter table(:links) do
      add :langs, {:array, :string}, default: []
    end

    # GIN index for efficient array containment queries
    create index(:links, [:langs], using: "gin")
  end
end
