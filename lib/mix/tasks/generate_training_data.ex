defmodule Mix.Tasks.GenerateTrainingData do
  @moduledoc """
  Generate training data for the ML tagger by classifying links with Ollama.

  Usage:
    mix generate_training_data --count 1000
    mix generate_training_data --count 500 --output priv/ml/training_data.json
  """
  use Mix.Task

  require Logger

  alias PokeAround.AI.Ollama
  alias PokeAround.Repo
  alias PokeAround.Links.Link
  import Ecto.Query

  @shortdoc "Generate training data using Ollama"

  @default_count 1000
  @default_output "priv/ml/training_data.json"
  @model "llama3.2:3b"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args,
      switches: [count: :integer, output: :string, resume: :boolean],
      aliases: [c: :count, o: :output, r: :resume]
    )

    count = opts[:count] || @default_count
    output_path = opts[:output] || @default_output
    resume = opts[:resume] || false

    Mix.Task.run("app.start")

    IO.puts("Generating training data...")
    IO.puts("  Count: #{count}")
    IO.puts("  Output: #{output_path}")

    seed_tags = load_seed_tags()
    IO.puts("  Seed tags: #{length(seed_tags)}")

    # Load existing data if resuming
    existing_data = if resume, do: load_existing(output_path), else: []
    existing_urls = MapSet.new(Enum.map(existing_data, & &1["url"]))
    IO.puts("  Existing samples: #{length(existing_data)}")

    # Check Ollama
    if not Ollama.available?() do
      IO.puts("\nError: Ollama is not available. Please start it first.")
      System.halt(1)
    end

    # Fetch links to classify
    links = fetch_links(count, existing_urls)
    IO.puts("\nFetched #{length(links)} links to classify\n")

    # Process links with progress
    {training_data, stats} = process_links(links, seed_tags, existing_data)

    # Save results
    File.mkdir_p!(Path.dirname(output_path))
    json = Jason.encode!(training_data, pretty: true)
    File.write!(output_path, json)

    IO.puts("\n\nResults:")
    IO.puts("  Total samples: #{length(training_data)}")
    IO.puts("  New samples: #{stats.processed}")
    IO.puts("  Errors: #{stats.errors}")
    IO.puts("  Saved to: #{output_path}")

    # Print tag distribution
    print_tag_stats(training_data)
  end

  defp fetch_links(count, exclude_urls) do
    # Get a mix of high-score and recent links
    high_score =
      from(l in Link,
        where: l.score >= 60,
        where: not is_nil(l.post_text),
        where: fragment("? && ?", l.langs, ^["en"]),
        order_by: [desc: l.score],
        limit: ^div(count, 2)
      )
      |> Repo.all()

    recent =
      from(l in Link,
        where: not is_nil(l.post_text),
        where: fragment("? && ?", l.langs, ^["en"]),
        order_by: [desc: l.inserted_at],
        limit: ^div(count, 2)
      )
      |> Repo.all()

    (high_score ++ recent)
    |> Enum.uniq_by(& &1.url)
    |> Enum.reject(fn link -> MapSet.member?(exclude_urls, link.url) end)
    |> Enum.take(count)
  end

  defp process_links(links, seed_tags, existing_data) do
    total = length(links)

    {new_data, stats} =
      links
      |> Enum.with_index(1)
      |> Enum.reduce({[], %{processed: 0, errors: 0}}, fn {link, idx}, {acc, stats} ->
        progress = Float.round(idx / total * 100, 1)
        IO.write("\r[#{progress}%] Processing #{idx}/#{total}...")

        case classify_link(link, seed_tags) do
          {:ok, sample} ->
            {[sample | acc], %{stats | processed: stats.processed + 1}}

          {:error, _reason} ->
            {acc, %{stats | errors: stats.errors + 1}}
        end
      end)

    {existing_data ++ Enum.reverse(new_data), stats}
  end

  defp classify_link(link, seed_tags) do
    prompt = build_prompt(link, seed_tags)

    case Ollama.generate(prompt, model: @model, temperature: 0.2) do
      {:ok, response} ->
        case parse_tags(response, seed_tags) do
          {:ok, tags} when tags != [] ->
            sample = %{
              "url" => link.url,
              "domain" => link.domain,
              "text" => String.slice(link.post_text || "", 0, 1000),
              "title" => extract_title(link),
              "tags" => tags,
              "source" => "ollama-#{@model}",
              "classified_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            }
            {:ok, sample}

          _ ->
            {:error, :no_valid_tags}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_prompt(link, seed_tags) do
    post_text = String.slice(link.post_text || "", 0, 500)
    url = link.url || ""
    domain = link.domain || ""

    tag_list = Enum.join(seed_tags, ", ")

    """
    You are a link categorization expert. Classify this shared link with 2-5 relevant tags.

    AVAILABLE TAGS (select ONLY from this list):
    #{tag_list}

    GUIDELINES:
    - Choose 2-5 tags that best describe the topic, format, and domain
    - Consider both the content type (article, video, tool, etc.) and subject matter
    - Prefer specific tags over generic ones when applicable
    - If the content is about programming, include the language/framework if identifiable

    POST TEXT: #{post_text}
    URL: #{url}
    DOMAIN: #{domain}

    Respond with ONLY a JSON array of tags, nothing else:
    """
  end

  defp parse_tags(response, seed_tags) do
    seed_set = MapSet.new(seed_tags)

    cleaned =
      response
      |> String.trim()
      |> String.replace(~r/^```json\s*/i, "")
      |> String.replace(~r/\s*```$/, "")
      |> String.trim()

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

  defp extract_title(link) do
    # Try to extract a title from the post text (often URLs have titles before/after them)
    link.post_text
    |> String.replace(~r/https?:\/\/[^\s]+/, "")
    |> String.trim()
    |> String.slice(0, 200)
  end

  defp load_seed_tags do
    path = Path.join(["priv", "data", "seed_tags.txt"])

    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))

      {:error, _} ->
        IO.puts("Warning: Could not load seed tags")
        []
    end
  end

  defp load_existing(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} when is_list(data) -> data
          _ -> []
        end
      {:error, _} -> []
    end
  end

  defp print_tag_stats(training_data) do
    tag_counts =
      training_data
      |> Enum.flat_map(& &1["tags"])
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_, count} -> -count end)

    IO.puts("\nTop 30 tags:")
    tag_counts
    |> Enum.take(30)
    |> Enum.each(fn {tag, count} ->
      IO.puts("  #{String.pad_trailing(tag, 20)} #{count}")
    end)

    IO.puts("\nUnique tags used: #{length(tag_counts)}")
  end
end
