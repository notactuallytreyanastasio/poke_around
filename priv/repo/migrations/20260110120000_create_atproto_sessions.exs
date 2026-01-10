defmodule PokeAround.Repo.Migrations.CreateAtprotoSessions do
  use Ecto.Migration

  def change do
    create table(:atproto_sessions) do
      add :user_did, :string, null: false
      add :handle, :string

      # OAuth tokens (encrypted at rest via application-level encryption)
      add :access_token, :text
      add :refresh_token, :text

      # DPoP keypair (serialized JSON)
      add :dpop_keypair, :text, null: false

      # Server endpoints
      add :pds_url, :string, null: false
      add :auth_server_url, :string

      # Session metadata
      add :scope, :string
      add :expires_at, :utc_datetime_usec

      # DPoP nonces (per-server)
      add :auth_server_nonce, :string
      add :resource_server_nonce, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:atproto_sessions, [:user_did])
    create index(:atproto_sessions, [:expires_at])
  end
end
