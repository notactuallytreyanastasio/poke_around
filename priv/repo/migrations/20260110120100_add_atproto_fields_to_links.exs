defmodule PokeAround.Repo.Migrations.AddAtprotoFieldsToLinks do
  use Ecto.Migration

  def change do
    alter table(:links) do
      # AT URI of synced record (e.g., at://did:plc:.../space.pokearound.link/...)
      add :at_uri, :string

      # When synced to PDS
      add :synced_at, :utc_datetime_usec

      # Sync status: nil, "pending", "synced", "failed"
      add :sync_status, :string
    end

    create index(:links, [:at_uri])
    create index(:links, [:sync_status])
  end
end
