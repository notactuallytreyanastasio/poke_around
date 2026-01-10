defmodule PokeAround.ATProto.Session do
  @moduledoc """
  Ecto schema for persisted ATProto OAuth sessions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias PokeAround.ATProto.{DPoP, OAuth}

  schema "atproto_sessions" do
    field :user_did, :string
    field :handle, :string

    field :access_token, :string
    field :refresh_token, :string

    field :dpop_keypair, :string
    field :pds_url, :string
    field :auth_server_url, :string

    field :scope, :string
    field :expires_at, :utc_datetime_usec

    field :auth_server_nonce, :string
    field :resource_server_nonce, :string

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:user_did, :dpop_keypair, :pds_url]
  @optional_fields [
    :handle,
    :access_token,
    :refresh_token,
    :auth_server_url,
    :scope,
    :expires_at,
    :auth_server_nonce,
    :resource_server_nonce
  ]

  def changeset(session, attrs) do
    session
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:user_did)
  end

  @doc """
  Convert an OAuth.Session struct to an Ecto-persistable map.
  """
  def from_oauth_session(%OAuth.Session{} = oauth_session) do
    %{
      user_did: oauth_session.did,
      handle: oauth_session.handle,
      access_token: oauth_session.access_token,
      refresh_token: oauth_session.refresh_token,
      dpop_keypair: oauth_session.dpop_keypair |> DPoP.serialize_keypair() |> Jason.encode!(),
      pds_url: oauth_session.pds_url,
      auth_server_url: oauth_session.auth_server_url,
      scope: oauth_session.scope,
      expires_at: oauth_session.expires_at,
      auth_server_nonce: oauth_session.auth_server_nonce,
      resource_server_nonce: oauth_session.resource_server_nonce
    }
  end

  @doc """
  Convert an Ecto session to an OAuth.Session struct.
  """
  def to_oauth_session(%__MODULE__{} = session) do
    %OAuth.Session{
      did: session.user_did,
      handle: session.handle,
      access_token: session.access_token,
      refresh_token: session.refresh_token,
      dpop_keypair: session.dpop_keypair |> Jason.decode!() |> DPoP.deserialize_keypair(),
      pds_url: session.pds_url,
      auth_server_url: session.auth_server_url,
      scope: session.scope,
      expires_at: session.expires_at,
      auth_server_nonce: session.auth_server_nonce,
      resource_server_nonce: session.resource_server_nonce
    }
  end

  @doc """
  Check if a session's access token is expired.
  """
  def expired?(%__MODULE__{expires_at: nil}), do: false

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Check if a session should be refreshed (expires within 5 minutes).
  """
  def should_refresh?(%__MODULE__{expires_at: nil}), do: false

  def should_refresh?(%__MODULE__{expires_at: expires_at}) do
    threshold = DateTime.utc_now() |> DateTime.add(5, :minute)
    DateTime.compare(threshold, expires_at) == :gt
  end
end
