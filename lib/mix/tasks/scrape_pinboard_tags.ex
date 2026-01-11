defmodule Mix.Tasks.ScrapePinboardTags do
  @moduledoc """
  Scrapes tags from public pinboard.in pages to build a comprehensive tag vocabulary.

  Usage:
    mix scrape_pinboard_tags
  """
  use Mix.Task

  @shortdoc "Scrape tags from pinboard.in public pages"

  @pages [
    "https://pinboard.in/popular/",
    "https://pinboard.in/recent/",
    "https://pinboard.in/recent/?page=2",
    "https://pinboard.in/recent/?page=3",
    "https://pinboard.in/recent/?page=4",
    "https://pinboard.in/recent/?page=5"
  ]

  # Popular tag pages for specific categories
  @tag_pages [
    "https://pinboard.in/t:programming/",
    "https://pinboard.in/t:javascript/",
    "https://pinboard.in/t:python/",
    "https://pinboard.in/t:design/",
    "https://pinboard.in/t:webdev/",
    "https://pinboard.in/t:tools/",
    "https://pinboard.in/t:security/",
    "https://pinboard.in/t:ai/",
    "https://pinboard.in/t:machinelearning/",
    "https://pinboard.in/t:linux/",
    "https://pinboard.in/t:opensource/",
    "https://pinboard.in/t:tutorial/",
    "https://pinboard.in/t:reference/",
    "https://pinboard.in/t:science/",
    "https://pinboard.in/t:history/",
    "https://pinboard.in/t:economics/",
    "https://pinboard.in/t:politics/",
    "https://pinboard.in/t:business/",
    "https://pinboard.in/t:startup/",
    "https://pinboard.in/t:productivity/",
    "https://pinboard.in/t:music/",
    "https://pinboard.in/t:video/",
    "https://pinboard.in/t:photography/",
    "https://pinboard.in/t:art/",
    "https://pinboard.in/t:writing/",
    "https://pinboard.in/t:books/",
    "https://pinboard.in/t:health/",
    "https://pinboard.in/t:food/",
    "https://pinboard.in/t:travel/",
    "https://pinboard.in/t:games/",
    "https://pinboard.in/t:funny/",
    "https://pinboard.in/t:culture/",
    "https://pinboard.in/t:philosophy/",
    "https://pinboard.in/t:environment/"
  ]

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("Scraping tags from pinboard.in...")

    all_tags =
      (@pages ++ @tag_pages)
      |> Enum.reduce(MapSet.new(), fn url, acc ->
        IO.puts("  Scraping #{url}...")

        case scrape_tags(url) do
          {:ok, tags} ->
            IO.puts("    Found #{length(tags)} tags")
            MapSet.union(acc, MapSet.new(tags))

          {:error, reason} ->
            IO.puts("    Error: #{reason}")
            acc
        end
      end)

    # Normalize and filter tags
    normalized_tags =
      all_tags
      |> Enum.map(&normalize_tag/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(String.length(&1) < 2))
      |> Enum.reject(&meta_tag?/1)
      |> Enum.uniq()
      |> Enum.sort()

    IO.puts("\nFound #{length(normalized_tags)} unique tags")

    # Write to seed_tags.txt
    output_path = Path.join(["priv", "ml", "seed_tags.txt"])
    File.mkdir_p!(Path.dirname(output_path))
    File.write!(output_path, Enum.join(normalized_tags, "\n"))

    IO.puts("Wrote tags to #{output_path}")

    # Also print some stats
    IO.puts("\nSample tags:")
    normalized_tags |> Enum.take(50) |> Enum.each(&IO.puts("  #{&1}"))
  end

  defp scrape_tags(url) do
    case Req.get(url, headers: [{"user-agent", "Mozilla/5.0 (compatible; tag-scraper)"}]) do
      {:ok, %{status: 200, body: body}} ->
        tags = extract_tags(body)
        {:ok, tags}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp extract_tags(html) do
    # Parse HTML and find all tag links (format: /t:tagname/)
    case Floki.parse_document(html) do
      {:ok, document} ->
        document
        |> Floki.find("a[href^='/t:']")
        |> Enum.map(fn element ->
          href = Floki.attribute(element, "href") |> List.first()
          extract_tag_from_href(href)
        end)
        |> Enum.reject(&is_nil/1)

      {:error, _} ->
        # Fallback to regex
        Regex.scan(~r{/t:([^/]+)/}, html)
        |> Enum.map(fn [_, tag] -> tag end)
    end
  end

  defp extract_tag_from_href(nil), do: nil
  defp extract_tag_from_href(href) do
    case Regex.run(~r{/t:([^/]+)/?}, href) do
      [_, tag] -> tag
      _ -> nil
    end
  end

  defp normalize_tag(tag) do
    tag
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]/, "")
    |> String.trim()
    |> case do
      "" -> nil
      t -> t
    end
  end

  # Filter out meta/system tags
  defp meta_tag?(tag) do
    String.starts_with?(tag, "via:") or
    String.starts_with?(tag, "for:") or
    String.starts_with?(tag, "from:") or
    String.starts_with?(tag, "ifttt") or
    String.starts_with?(tag, "pocket") or
    String.starts_with?(tag, "instapaper") or
    tag in ["unread", "toread", "read-later", "readlater", "todo", "starred"]
  end
end
