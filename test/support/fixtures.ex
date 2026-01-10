defmodule PokeAround.Fixtures do
  @moduledoc """
  Test fixtures for PokeAround tests.
  """

  alias PokeAround.Repo
  alias PokeAround.Links.Link
  alias PokeAround.Tags.Tag

  @doc """
  Create a link with default values.
  """
  def link_fixture(attrs \\ %{}) do
    url = attrs[:url] || "https://example.com/article-#{System.unique_integer([:positive])}"

    {:ok, link} =
      %Link{}
      |> Link.changeset(
        Map.merge(
          %{
            url: url,
            url_hash: Link.hash_url(url),
            post_text: attrs[:post_text] || "A post about interesting things",
            domain: attrs[:domain] || "example.com",
            score: attrs[:score] || 50,
            langs: attrs[:langs] || ["en"],
            author_handle: attrs[:author_handle] || "testuser.bsky.social",
            author_followers_count: attrs[:author_followers_count] || 1000
          },
          Map.drop(attrs, [:url, :post_text, :domain, :score, :langs, :author_handle, :author_followers_count])
        )
      )
      |> Repo.insert()

    link
  end

  @doc """
  Create a tag with default values.
  """
  def tag_fixture(attrs \\ %{}) do
    name = attrs[:name] || "test-tag-#{System.unique_integer([:positive])}"

    {:ok, tag} =
      %Tag{}
      |> Tag.changeset(%{
        name: name,
        slug: Tag.slugify(name),
        usage_count: attrs[:usage_count] || 0
      })
      |> Repo.insert()

    tag
  end

  @doc """
  Create a link with tags already associated.
  """
  def tagged_link_fixture(attrs \\ %{}, tag_names \\ ["test-tag"]) do
    link = link_fixture(Map.put(attrs, :tagged_at, DateTime.utc_now()))

    Enum.each(tag_names, fn name ->
      tag = tag_fixture(%{name: name})
      Repo.insert_all("link_tags", [
        %{
          link_id: link.id,
          tag_id: tag.id,
          source: "test",
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
      ])
    end)

    Repo.get!(Link, link.id)
  end

  @doc """
  Create multiple untagged links for testing batch processing.
  """
  def untagged_links_fixture(count, attrs \\ %{}) do
    Enum.map(1..count, fn i ->
      link_fixture(
        Map.merge(attrs, %{
          post_text: "Untagged link number #{i} about various topics",
          tagged_at: nil
        })
      )
    end)
  end
end
