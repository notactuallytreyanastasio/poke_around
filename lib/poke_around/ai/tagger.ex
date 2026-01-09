defmodule PokeAround.AI.Tagger do
  @moduledoc """
  GenServer that continuously processes untagged links using Ollama.

  Runs independently as a background worker, picking up untagged links
  and enriching them with AI-generated tags.

  ## Usage

      # Start via supervisor
      children = [PokeAround.AI.Tagger]

  ## Configuration

      config :poke_around, PokeAround.AI.Tagger,
        enabled: true,
        model: "qwen3:8b",
        batch_size: 5,
        interval_ms: 10_000
  """

  use GenServer

  require Logger

  alias PokeAround.AI.Ollama
  alias PokeAround.Tags

  @default_interval_ms 10_000
  @default_batch_size 5
  @default_model "qwen3:8b"

  defstruct [
    :model,
    :batch_size,
    :interval_ms,
    :enabled,
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
  Enable or disable the tagger.
  """
  def set_enabled(enabled, server \\ __MODULE__) do
    GenServer.call(server, {:set_enabled, enabled})
  end

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    config = Application.get_env(:poke_around, __MODULE__, [])

    state = %__MODULE__{
      model: opts[:model] || config[:model] || @default_model,
      batch_size: opts[:batch_size] || config[:batch_size] || @default_batch_size,
      interval_ms: opts[:interval_ms] || config[:interval_ms] || @default_interval_ms,
      enabled: opts[:enabled] != false && config[:enabled] != false
    }

    if state.enabled do
      # Check if Ollama is available before starting
      if Ollama.available?() do
        Logger.info("Tagger started: model=#{state.model}, batch=#{state.batch_size}, interval=#{state.interval_ms}ms")
        schedule_run(state.interval_ms)
      else
        Logger.warning("Tagger: Ollama not available, will retry")
        schedule_run(30_000)
      end
    else
      Logger.info("Tagger started in disabled mode")
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
    stats = %{
      enabled: state.enabled,
      model: state.model,
      processed: state.processed,
      errors: state.errors,
      last_run: state.last_run,
      untagged_count: Tags.count_untagged()
    }

    {:reply, stats, state}
  end

  @impl GenServer
  def handle_call({:set_enabled, enabled}, _from, state) do
    Logger.info("Tagger #{if enabled, do: "enabled", else: "disabled"}")
    {:reply, :ok, %{state | enabled: enabled}}
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp schedule_run(interval_ms) do
    Process.send_after(self(), :run, interval_ms)
  end

  defp process_batch(state) do
    links = Tags.untagged_links(state.batch_size)

    if links == [] do
      state
    else
      Logger.debug("Tagger: processing #{length(links)} links")

      Enum.reduce(links, state, fn link, acc ->
        case tag_link(link, state.model) do
          {:ok, tags} ->
            Logger.debug("Tagger: tagged link #{link.id} with #{inspect(tags)}")
            %{acc | processed: acc.processed + 1}

          {:error, reason} ->
            Logger.warning("Tagger: failed to tag link #{link.id}: #{inspect(reason)}")
            %{acc | errors: acc.errors + 1}
        end
      end)
    end
  end

  defp tag_link(link, model) do
    prompt = build_prompt(link)

    case Ollama.generate(prompt, model: model) do
      {:ok, response} ->
        case parse_tags(response) do
          {:ok, tags} when tags != [] ->
            Tags.tag_link(link, tags, source: "ollama")
            {:ok, tags}

          {:ok, []} ->
            # No tags extracted, mark as processed anyway
            Tags.tag_link(link, ["untagged"], source: "ollama")
            {:ok, ["untagged"]}

          {:error, reason} ->
            {:error, {:parse_error, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_prompt(link) do
    post_text = link.post_text || ""
    url = link.url || ""
    domain = link.domain || ""

    """
    You are a link categorization assistant. Given a social media post and a link, suggest 3-5 tags that would help humans browse and discover this content.

    Rules:
    - Tags must be single words or hyphenated (no spaces)
    - Tags should be lowercase
    - Focus on the topic, technology, or category
    - Be specific but not too narrow
    - Avoid generic tags like "interesting" or "cool"

    Post: #{String.slice(post_text, 0, 500)}
    URL: #{url}
    Domain: #{domain}

    Respond with ONLY a JSON array of tags. Example: ["javascript", "web-dev", "tutorial"]
    """
  end

  defp parse_tags(response) do
    # Try to extract JSON array from response
    # The model might include thinking or extra text

    # First, try direct JSON parse
    case Jason.decode(String.trim(response)) do
      {:ok, tags} when is_list(tags) ->
        {:ok, normalize_tags(tags)}

      _ ->
        # Try to find JSON array in the response
        case Regex.run(~r/\[([^\]]+)\]/, response) do
          [match | _] ->
            case Jason.decode(match) do
              {:ok, tags} when is_list(tags) ->
                {:ok, normalize_tags(tags)}

              _ ->
                {:error, :no_valid_json}
            end

          nil ->
            {:error, :no_json_array}
        end
    end
  end

  defp normalize_tags(tags) do
    tags
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.map(&String.replace(&1, ~r/\s+/, "-"))
    |> Enum.map(&String.replace(&1, ~r/[^a-z0-9\-]/, ""))
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(5)
  end
end
