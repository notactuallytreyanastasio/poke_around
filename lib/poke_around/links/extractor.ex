defmodule PokeAround.Links.Extractor do
  @moduledoc """
  Extracts and filters links from the firehose.

  Subscribes to firehose events, parses posts, extracts links,
  and applies quality filtering based on author metrics.

  ## Usage

      # Start via supervisor
      children = [PokeAround.Links.Extractor]

  Qualified links are broadcast to "links:extracted":

      Phoenix.PubSub.subscribe(PokeAround.PubSub, "links:extracted")
      # Receive: {:link, %{url: "...", post: %Post{}, score: 85}}
  """

  use GenServer

  require Logger

  alias PokeAround.Bluesky.Parser
  alias PokeAround.Links

  @min_followers 100
  @stats_interval_ms 30_000

  defstruct [
    :started_at,
    posts_processed: 0,
    links_found: 0,
    links_qualified: 0
  ]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      type: :worker
    }
  end

  def get_stats(server \\ __MODULE__) do
    GenServer.call(server, :get_stats)
  end

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(_opts) do
    Phoenix.PubSub.subscribe(PokeAround.PubSub, "firehose:events")
    schedule_stats_log()

    state = %__MODULE__{started_at: DateTime.utc_now()}
    Logger.info("Link extractor started, min followers: #{@min_followers}")

    {:ok, state}
  end

  @impl GenServer
  def handle_info({:post, event}, state) do
    state = process_post(event, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:log_stats, state) do
    log_stats(state)
    schedule_stats_log()
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def handle_call(:get_stats, _from, state) do
    {:reply, build_stats(state), state}
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp process_post(event, state) do
    case Parser.parse_post(event) do
      {:ok, post} ->
        state = %{state | posts_processed: state.posts_processed + 1}
        links = Parser.extract_links(post)

        if links != [] do
          state = %{state | links_found: state.links_found + length(links)}
          process_links(links, post, state)
        else
          state
        end

      {:error, _} ->
        state
    end
  end

  defp process_links(links, post, state) do
    qualified_count =
      links
      |> Enum.filter(fn _url -> qualifies?(post) end)
      |> Enum.map(fn url -> store_link(url, post) end)
      |> Enum.count(fn result -> result == :ok end)

    %{state | links_qualified: state.links_qualified + qualified_count}
  end

  defp qualifies?(%{author: nil}), do: false
  defp qualifies?(%{is_reply: true}), do: false

  defp qualifies?(%{author: author}) do
    followers = author.followers_count || 0
    followers >= @min_followers
  end

  defp store_link(url, post) do
    attrs = %{
      url: url,
      post_uri: post.uri,
      post_text: post.text,
      post_created_at: post.created_at,
      author_did: post.author && post.author.did,
      author_handle: post.author && post.author.handle,
      author_display_name: post.author && post.author.display_name,
      author_followers_count: post.author && post.author.followers_count,
      score: calculate_score(post)
    }

    case Links.store_link(attrs) do
      {:ok, :exists} -> :exists
      {:ok, _link} -> :ok
      {:error, _} -> :error
    end
  end

  defp calculate_score(%{author: nil}), do: 0

  defp calculate_score(%{author: author}) do
    followers = author.followers_count || 0

    # Simple log-based score: more followers = higher score, but diminishing returns
    # Score range: 0-100
    base_score = :math.log10(max(followers, 1)) * 20
    min(round(base_score), 100)
  end

  defp build_stats(state) do
    uptime = DateTime.diff(DateTime.utc_now(), state.started_at, :second)

    %{
      posts_processed: state.posts_processed,
      links_found: state.links_found,
      links_qualified: state.links_qualified,
      uptime_seconds: uptime,
      qualification_rate:
        if(state.links_found > 0, do: state.links_qualified / state.links_found, else: 0.0)
    }
  end

  defp log_stats(state) do
    stats = build_stats(state)

    Logger.info(
      "Extractor: #{stats.posts_processed} posts, " <>
        "#{stats.links_found} links found, " <>
        "#{stats.links_qualified} qualified (#{Float.round(stats.qualification_rate * 100, 1)}%)"
    )
  end

  defp schedule_stats_log do
    Process.send_after(self(), :log_stats, @stats_interval_ms)
  end
end
