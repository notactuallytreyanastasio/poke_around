defmodule PokeAround.ATProto.Sync do
  @moduledoc """
  Background worker that syncs curated links to the service account's PDS.

  Only syncs links with score >= configured threshold (default 50).
  Runs periodically and processes links in batches.

  ## Configuration

  Configure in runtime.exs:

      config :poke_around, PokeAround.ATProto,
        sync_min_score: 50,
        sync_enabled: true

  ## Requirements

  Requires a service account session stored in the database.
  The service account must be authenticated via OAuth first.
  """

  use GenServer

  import Ecto.Query

  alias PokeAround.ATProto.{Client, Lexicon, TID}
  alias PokeAround.Links.Link
  alias PokeAround.Repo

  require Logger

  @collection "space.pokearound.link"
  @sync_interval_ms 60_000
  @batch_size 20

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually trigger a sync cycle.
  """
  def sync_now do
    GenServer.cast(__MODULE__, :sync)
  end

  @doc """
  Sync a single link immediately.
  """
  def sync_link(link_id) do
    GenServer.call(__MODULE__, {:sync_link, link_id})
  end

  @doc """
  Get sync statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    state = %{
      enabled: sync_enabled?(),
      min_score: get_min_score(),
      service_did: nil,
      synced_count: 0,
      failed_count: 0,
      last_sync: nil
    }

    if state.enabled do
      # Schedule first sync after a short delay
      Process.send_after(self(), :sync, 5_000)
    end

    {:ok, state}
  end

  @impl true
  def handle_cast(:sync, state) do
    {:noreply, do_sync(state)}
  end

  @impl true
  def handle_call({:sync_link, link_id}, _from, state) do
    result = sync_single_link(link_id, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      enabled: state.enabled,
      min_score: state.min_score,
      service_did: state.service_did,
      synced_count: state.synced_count,
      failed_count: state.failed_count,
      last_sync: state.last_sync
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:sync, state) do
    new_state = do_sync(state)

    # Schedule next sync
    if state.enabled do
      Process.send_after(self(), :sync, @sync_interval_ms)
    end

    {:noreply, new_state}
  end

  # Private functions

  defp do_sync(state) do
    if not state.enabled do
      state
    else
      case get_service_session() do
        {:ok, session} ->
          links = get_links_to_sync(state.min_score, @batch_size)

          {synced, failed, updated_session} =
            Enum.reduce(links, {0, 0, session}, fn link, {s, f, sess} ->
              case sync_link_to_pds(link, sess) do
                {:ok, new_sess} -> {s + 1, f, new_sess}
                {:error, _} -> {s, f + 1, sess}
              end
            end)

          # Save updated session (nonces may have changed)
          if synced > 0 or failed > 0 do
            Client.save_session(updated_session)
          end

          Logger.info("ATProto sync complete: #{synced} synced, #{failed} failed")

          %{
            state
            | service_did: session.did,
              synced_count: state.synced_count + synced,
              failed_count: state.failed_count + failed,
              last_sync: DateTime.utc_now()
          }

        {:error, :no_service_account} ->
          Logger.debug("ATProto sync: No service account configured")
          state

        {:error, reason} ->
          Logger.warning("ATProto sync: Failed to get session: #{inspect(reason)}")
          state
      end
    end
  end

  defp sync_single_link(link_id, _state) do
    case get_service_session() do
      {:ok, session} ->
        case Repo.get(Link, link_id) do
          nil ->
            {:error, :not_found}

          link ->
            sync_link_to_pds(link, session)
        end

      error ->
        error
    end
  end

  defp sync_link_to_pds(link, session) do
    record =
      link
      |> Lexicon.LinkRecord.from_db()
      |> Lexicon.LinkRecord.to_record()

    rkey = TID.generate()

    case Client.create_record(session, @collection, record, rkey: rkey) do
      {:ok, %{uri: uri, cid: _cid}, updated_session} ->
        # Update the link with AT URI
        link
        |> Link.changeset(%{
          at_uri: uri,
          synced_at: DateTime.utc_now(),
          sync_status: "synced"
        })
        |> Repo.update()

        {:ok, updated_session}

      {:error, reason} = error ->
        Logger.warning("Failed to sync link #{link.id}: #{inspect(reason)}")

        # Mark as failed
        link
        |> Link.changeset(%{sync_status: "failed"})
        |> Repo.update()

        error
    end
  end

  defp get_links_to_sync(min_score, limit) do
    from(l in Link,
      where: l.score >= ^min_score,
      where: is_nil(l.sync_status) or l.sync_status == "pending",
      where: is_nil(l.at_uri),
      order_by: [desc: l.score, asc: l.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp get_service_session do
    # Get the service account DID from config or first session
    case get_service_did() do
      nil ->
        {:error, :no_service_account}

      did ->
        Client.get_session(did)
    end
  end

  defp get_service_did do
    # For now, use the first session in the database as the service account
    # In production, you'd want to configure this explicitly
    case Repo.one(from(s in PokeAround.ATProto.Session, limit: 1, select: s.user_did)) do
      nil -> nil
      did -> did
    end
  end

  defp sync_enabled? do
    Application.get_env(:poke_around, PokeAround.ATProto, [])
    |> Keyword.get(:sync_enabled, false)
  end

  defp get_min_score do
    Application.get_env(:poke_around, PokeAround.ATProto, [])
    |> Keyword.get(:sync_min_score, 50)
  end
end
