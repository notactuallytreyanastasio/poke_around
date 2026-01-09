defmodule PokeAround.Repo.Migrations.CreateTagsTables do
  use Ecto.Migration

  def change do
    # Normalized tags table
    create table(:tags) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :usage_count, :integer, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tags, [:slug])
    create index(:tags, [:usage_count])

    # Join table for links <-> tags (many-to-many)
    create table(:link_tags, primary_key: false) do
      add :link_id, references(:links, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false
      add :source, :string, default: "ollama"  # "ollama", "user", "firehose"
      add :confidence, :float  # Model confidence if available

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:link_tags, [:link_id, :tag_id])
    create index(:link_tags, [:tag_id])

    # Track which links have been processed by tagger
    alter table(:links) do
      add :tagged_at, :utc_datetime_usec
    end

    create index(:links, [:tagged_at])
  end
end
