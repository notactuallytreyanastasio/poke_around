defmodule PokeAround.ATProto.Client do
  @moduledoc """
  High-level ATProto client for PDS interactions.

  Wraps OAuth session management and provides XRPC operations
  for creating, reading, and deleting records.
  """

  alias PokeAround.ATProto.{OAuth, TID}
  alias PokeAround.ATProto.Session, as: SessionSchema
  alias PokeAround.Repo

  require Logger

  @doc """
  Create a record in a user's PDS.

  ## Parameters

  - `session` - OAuth.Session
  - `collection` - Collection NSID (e.g., "space.pokearound.link")
  - `record` - Record data as a map
  - `opts` - Optional parameters:
    - `:rkey` - Record key (default: auto-generate TID)

  ## Returns

  `{:ok, %{uri: at_uri, cid: cid}, updated_session}` on success.
  """
  def create_record(session, collection, record, opts \\ []) do
    rkey = opts[:rkey] || TID.generate()
    url = "#{session.pds_url}/xrpc/com.atproto.repo.createRecord"

    body = %{
      "repo" => session.did,
      "collection" => collection,
      "rkey" => rkey,
      "record" => record
    }

    case OAuth.authenticated_request(session, :post, url, json: body) do
      {:ok, %{status: 200, body: response}, updated_session} ->
        {:ok, %{uri: response["uri"], cid: response["cid"]}, updated_session}

      {:ok, %{status: status, body: body}, _session} ->
        {:error, {:create_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get a record from a user's PDS.

  ## Parameters

  - `session` - OAuth.Session
  - `collection` - Collection NSID
  - `rkey` - Record key
  """
  def get_record(session, collection, rkey) do
    url = "#{session.pds_url}/xrpc/com.atproto.repo.getRecord"
    params = [repo: session.did, collection: collection, rkey: rkey]

    case OAuth.authenticated_request(session, :get, url, params: params) do
      {:ok, %{status: 200, body: response}, updated_session} ->
        {:ok, response, updated_session}

      {:ok, %{status: 404}, _session} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}, _session} ->
        {:error, {:get_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  List records in a collection.

  ## Parameters

  - `session` - OAuth.Session
  - `collection` - Collection NSID
  - `opts` - Optional parameters:
    - `:limit` - Max records to return (default: 50)
    - `:cursor` - Pagination cursor
    - `:reverse` - Reverse order
  """
  def list_records(session, collection, opts \\ []) do
    url = "#{session.pds_url}/xrpc/com.atproto.repo.listRecords"

    params =
      [repo: session.did, collection: collection]
      |> maybe_add(:limit, opts[:limit])
      |> maybe_add(:cursor, opts[:cursor])
      |> maybe_add(:reverse, opts[:reverse])

    case OAuth.authenticated_request(session, :get, url, params: params) do
      {:ok, %{status: 200, body: response}, updated_session} ->
        {:ok, response, updated_session}

      {:ok, %{status: status, body: body}, _session} ->
        {:error, {:list_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Delete a record from a user's PDS.

  ## Parameters

  - `session` - OAuth.Session
  - `collection` - Collection NSID
  - `rkey` - Record key
  """
  def delete_record(session, collection, rkey) do
    url = "#{session.pds_url}/xrpc/com.atproto.repo.deleteRecord"

    body = %{
      "repo" => session.did,
      "collection" => collection,
      "rkey" => rkey
    }

    case OAuth.authenticated_request(session, :post, url, json: body) do
      {:ok, %{status: 200}, updated_session} ->
        {:ok, updated_session}

      {:ok, %{status: status, body: body}, _session} ->
        {:error, {:delete_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get a session for a user from the database, refreshing if needed.
  """
  def get_session(user_did) do
    case Repo.get_by(SessionSchema, user_did: user_did) do
      nil ->
        {:error, :not_found}

      db_session ->
        oauth_session = SessionSchema.to_oauth_session(db_session)

        if SessionSchema.should_refresh?(db_session) do
          refresh_and_save(db_session, oauth_session)
        else
          {:ok, oauth_session}
        end
    end
  end

  @doc """
  Update the stored session after making requests.

  Call this after operations that may update nonces.
  """
  def save_session(%OAuth.Session{} = session) do
    attrs = SessionSchema.from_oauth_session(session)

    case Repo.get_by(SessionSchema, user_did: session.did) do
      nil ->
        %SessionSchema{}
        |> SessionSchema.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> SessionSchema.changeset(attrs)
        |> Repo.update()
    end
  end

  # Private functions

  defp refresh_and_save(db_session, oauth_session) do
    case OAuth.refresh_session(oauth_session) do
      {:ok, refreshed} ->
        attrs = SessionSchema.from_oauth_session(refreshed)

        db_session
        |> SessionSchema.changeset(attrs)
        |> Repo.update()

        {:ok, refreshed}

      {:error, reason} ->
        Logger.warning("Failed to refresh session for #{oauth_session.did}: #{inspect(reason)}")
        # Return the old session anyway, it might still work
        {:ok, oauth_session}
    end
  end

  defp maybe_add(params, _key, nil), do: params
  defp maybe_add(params, key, value), do: [{key, value} | params]
end
