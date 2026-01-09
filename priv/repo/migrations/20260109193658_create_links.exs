defmodule PokeAround.Repo.Migrations.CreateLinks do
  use Ecto.Migration

  def change do
    create table(:links) do
      # The actual URL
      add :url, :text, null: false

      # Normalized URL for deduplication (lowercase, no trailing slash, etc.)
      add :url_hash, :string, null: false

      # Source post info
      add :post_uri, :string
      add :post_text, :text
      add :post_created_at, :utc_datetime_usec

      # Author info (denormalized for fast reads)
      add :author_did, :string
      add :author_handle, :string
      add :author_display_name, :string
      add :author_followers_count, :integer

      # Quality score (0-100)
      add :score, :integer, default: 0

      # Link metadata (fetched later via unfurl)
      add :title, :text
      add :description, :text
      add :image_url, :text
      add :domain, :string

      # Tags for categorization
      add :tags, {:array, :string}, default: []

      # State
      add :stumble_count, :integer, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    # Unique on normalized URL hash
    create unique_index(:links, [:url_hash])

    # For random stumbling - fetch random links efficiently
    create index(:links, [:score])
    create index(:links, [:inserted_at])
    create index(:links, [:domain])

    # For filtering by tags
    create index(:links, [:tags], using: "gin")
  end
end
