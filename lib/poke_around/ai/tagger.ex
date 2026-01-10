defmodule PokeAround.AI.Tagger do
  @moduledoc """
  GenServer that tags links using Ollama with a curated tag vocabulary.

  Uses a seed list of ~300 tags to guide the LLM toward consistent categorization.
  Falls back to generating new tags if none of the seed tags fit.

  ## Configuration

      config :poke_around, PokeAround.AI.Tagger,
        enabled: true,
        model: "llama3.2:3b",
        batch_size: 10,
        interval_ms: 10_000,
        langs: ["en"]
  """

  use GenServer

  require Logger

  alias PokeAround.AI.Ollama
  alias PokeAround.Tags
  alias PokeAround.Repo
  alias PokeAround.Links.Link
  import Ecto.Query

  @default_model "llama3.2:3b"
  @default_batch_size 10
  @default_interval_ms 10_000
  @seed_tags_path "priv/data/seed_tags.txt"

  defstruct [
    :model,
    :batch_size,
    :interval_ms,
    :enabled,
    :seed_tags,
    :langs,
    processed: 0,
    errors: 0,
    last_run: nil
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

  @doc """
  Get tagger stats.
  """
  def stats(server \\ __MODULE__) do
    GenServer.call(server, :stats)
  end

  @doc """
  Manually trigger a processing run.
  """
  def process_now(server \\ __MODULE__) do
    GenServer.cast(server, :process_now)
  end

  @doc """
  Tag a single link (for testing).
  """
  def tag_one(link_id, server \\ __MODULE__) do
    GenServer.call(server, {:tag_one, link_id}, 60_000)
  end

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    config = Application.get_env(:poke_around, __MODULE__, [])

    seed_tags = load_seed_tags()

    state = %__MODULE__{
      model: opts[:model] || config[:model] || @default_model,
      batch_size: opts[:batch_size] || config[:batch_size] || @default_batch_size,
      interval_ms: opts[:interval_ms] || config[:interval_ms] || @default_interval_ms,
      enabled: Keyword.get(opts, :enabled, Keyword.get(config, :enabled, true)),
      langs: opts[:langs] || config[:langs] || ["en"],
      seed_tags: seed_tags
    }

    if state.enabled do
      if Ollama.available?() do
        Logger.info("Tagger ready: #{length(seed_tags)} seed tags, model=#{state.model}")
        schedule_run(state.interval_ms)
      else
        Logger.warning("Tagger: Ollama not available, will retry in 30s")
        schedule_run(30_000)
      end
    end

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:run, %{enabled: false} = state) do
    schedule_run(state.interval_ms)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:run, state) do
    state = process_batch(state)
    schedule_run(state.interval_ms)
    {:noreply, %{state | last_run: DateTime.utc_now()}}
  end

  @impl GenServer
  def handle_cast(:process_now, state) do
    state = process_batch(state)
    {:noreply, %{state | last_run: DateTime.utc_now()}}
  end

  @impl GenServer
  def handle_call(:stats, _from, state) do
    untagged = count_untagged(state.langs)

    stats = %{
      enabled: state.enabled,
      model: state.model,
      processed: state.processed,
      errors: state.errors,
      last_run: state.last_run,
      untagged_count: untagged,
      seed_tags_count: length(state.seed_tags)
    }

    {:reply, stats, state}
  end

  @impl GenServer
  def handle_call({:tag_one, link_id}, _from, state) do
    link = Repo.get(Link, link_id)

    if link do
      result = tag_link(link, state)
      {:reply, result, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp schedule_run(interval_ms) do
    Process.send_after(self(), :run, interval_ms)
  end

  defp process_batch(state) do
    if not Ollama.available?() do
      Logger.warning("Tagger: Ollama not available, skipping")
      state
    else
      links = fetch_untagged_links(state.batch_size, state.langs)

      if links == [] do
        state
      else
        {processed, errors} =
          Enum.reduce(links, {0, 0}, fn link, {p, e} ->
            case tag_link(link, state) do
              {:ok, _tags} -> {p + 1, e}
              {:error, _} -> {p, e + 1}
            end
          end)

        new_processed = state.processed + processed
        new_errors = state.errors + errors

        # Calculate rate
        uptime_mins = max(DateTime.diff(DateTime.utc_now(), state.last_run || DateTime.utc_now()) / 60, 1)
        rate = Float.round(new_processed / max(uptime_mins, 0.1), 1)

        Logger.info("Tagger: #{processed}/#{length(links)} tagged | #{new_processed} total | #{rate}/min")

        %{state | processed: new_processed, errors: new_errors}
      end
    end
  end

  defp fetch_untagged_links(limit, langs) do
    query =
      from(l in Link,
        where: is_nil(l.tagged_at),
        where: not is_nil(l.post_text),
        order_by: [desc: l.score, desc: l.inserted_at],
        limit: ^limit
      )

    query =
      if langs != [] do
        from(l in query, where: fragment("? && ?", l.langs, ^langs))
      else
        query
      end

    Repo.all(query)
  end

  defp count_untagged(langs) do
    query =
      from(l in Link,
        where: is_nil(l.tagged_at),
        where: not is_nil(l.post_text)
      )

    query =
      if langs != [] do
        from(l in query, where: fragment("? && ?", l.langs, ^langs))
      else
        query
      end

    Repo.aggregate(query, :count)
  end

  defp tag_link(link, state) do
    prompt = build_prompt(link, state.seed_tags)

    case Ollama.generate(prompt, model: state.model, temperature: 0.3) do
      {:ok, response} ->
        case parse_tags(response, state.seed_tags) do
          {:ok, tags} when tags != [] ->
            Tags.tag_link(link, tags, source: "ollama")
            log_tagged(link, tags)
            {:ok, tags}

          {:ok, []} ->
            # No tags - mark as needs-review
            Tags.tag_link(link, ["needs-review"], source: "ollama-uncertain")
            {:ok, ["needs-review"]}

          {:error, _reason} ->
            Tags.tag_link(link, ["needs-review"], source: "ollama-parse-error")
            {:ok, ["needs-review"]}
        end

      {:error, reason} ->
        Logger.debug("Tagger: Ollama error for link #{link.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_prompt(link, seed_tags) do
    post_text = String.slice(link.post_text || "", 0, 500)
    url = link.url || ""
    domain = link.domain || ""

    # Group tags by first letter for readability
    tag_list = Enum.join(seed_tags, ", ")

    """
    You are a link categorization assistant. Given a social media post and URL, select 2-5 tags from the provided list that best describe the content.

    AVAILABLE TAGS (choose ONLY from this list):
    #{tag_list}

    RULES:
    - Select 2-5 tags that accurately describe the content
    - Only use tags from the list above
    - If nothing fits well, return an empty array []
    - Respond with ONLY a JSON array, no explanation

    POST: #{post_text}
    URL: #{url}
    DOMAIN: #{domain}

    JSON array of tags:
    """
  end

  defp parse_tags(response, seed_tags) do
    seed_set = MapSet.new(seed_tags)

    # Clean up the response
    cleaned =
      response
      |> String.trim()
      |> String.replace(~r/^```json\s*/i, "")
      |> String.replace(~r/\s*```$/, "")
      |> String.trim()

    # Try direct JSON parse
    case Jason.decode(cleaned) do
      {:ok, tags} when is_list(tags) ->
        valid_tags =
          tags
          |> Enum.filter(&is_binary/1)
          |> Enum.map(&String.downcase/1)
          |> Enum.map(&String.replace(&1, ~r/\s+/, "-"))
          |> Enum.filter(&MapSet.member?(seed_set, &1))
          |> Enum.take(5)

        {:ok, valid_tags}

      _ ->
        # Try to extract array from response
        case Regex.run(~r/\[([^\]]*)\]/, cleaned) do
          [match | _] ->
            case Jason.decode(match) do
              {:ok, tags} when is_list(tags) ->
                valid_tags =
                  tags
                  |> Enum.filter(&is_binary/1)
                  |> Enum.map(&String.downcase/1)
                  |> Enum.filter(&MapSet.member?(seed_set, &1))
                  |> Enum.take(5)

                {:ok, valid_tags}

              _ ->
                {:error, :invalid_json}
            end

          nil ->
            {:error, :no_array_found}
        end
    end
  end

  defp load_seed_tags do
    path = Application.app_dir(:poke_around, @seed_tags_path)

    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))

      {:error, _} ->
        Logger.warning("Tagger: Could not load seed tags from #{path}")
        []
    end
  end

  defp log_tagged(link, tags) do
    preview =
      link.post_text
      |> String.slice(0, 60)
      |> String.replace(~r/\s+/, " ")

    Logger.debug("Tagged ##{link.id}: [#{Enum.join(tags, ", ")}] - #{preview}...")
  end
end
