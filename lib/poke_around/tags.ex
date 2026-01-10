defmodule PokeAround.Tags do
  @moduledoc """
  Context for managing tags and link-tag associations.
  """

  import Ecto.Query
  alias PokeAround.Repo
  alias PokeAround.Tags.{Tag, LinkTag}
  alias PokeAround.Links.Link

  @doc """
  Get or create a tag by name.
  """
  def get_or_create_tag(name) when is_binary(name) do
    slug = Tag.slugify(name)

    case Repo.get_by(Tag, slug: slug) do
      nil ->
        %Tag{}
        |> Tag.changeset(%{name: name, slug: slug})
        |> Repo.insert()

      tag ->
        {:ok, tag}
    end
  end

  @doc """
  Tag a link with multiple tags.

  Takes a link and a list of tag names, creates any missing tags,
  and associates them with the link.
  """
  def tag_link(link, tag_names, opts \\ []) when is_list(tag_names) do
    source = opts[:source] || "axon"
    confidence = opts[:confidence]

    result = Repo.transaction(fn ->
      tag_ids =
        tag_names
        |> Enum.map(&get_or_create_tag/1)
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, tag} -> tag.id end)

      # Create link_tag associations
      now = DateTime.utc_now()

      link_tags =
        Enum.map(tag_ids, fn tag_id ->
          %{
            link_id: link.id,
            tag_id: tag_id,
            source: source,
            confidence: confidence,
            inserted_at: now,
            updated_at: now
          }
        end)

      # Insert all, ignoring conflicts (tag might already be associated)
      Repo.insert_all(LinkTag, link_tags, on_conflict: :nothing)

      # Update usage counts
      from(t in Tag, where: t.id in ^tag_ids)
      |> Repo.update_all(inc: [usage_count: 1])

      # Mark link as tagged
      from(l in Link, where: l.id == ^link.id)
      |> Repo.update_all(set: [tagged_at: now])

      :ok
    end)

    # Broadcast tagging result for live ingestion view
    case result do
      {:ok, :ok} ->
        Phoenix.PubSub.broadcast(
          PokeAround.PubSub,
          "links:tagged",
          {:link_tagged, %{link_id: link.id, tags: tag_names, source: source}}
        )

      _ ->
        :ok
    end

    result
  end

  @doc """
  Get all tags for a link.
  """
  def get_tags_for_link(link_id) do
    from(t in Tag,
      join: lt in LinkTag,
      on: lt.tag_id == t.id,
      where: lt.link_id == ^link_id,
      select: t
    )
    |> Repo.all()
  end

  @doc """
  Get popular tags.
  """
  def popular_tags(limit \\ 20) do
    from(t in Tag,
      order_by: [desc: t.usage_count],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Get links by tag slug.

  Options:
  - `:limit` - Max links to return (default: 50)
  - `:order` - :newest (default) or :score
  - `:langs` - Filter by languages (empty list = all)
  """
  def links_by_tag(slug, opts \\ []) do
    limit = opts[:limit] || 50
    order = opts[:order] || :newest
    langs = opts[:langs] || []

    order_by = case order do
      :newest -> [desc: :inserted_at]
      :score -> [desc: :score]
    end

    query = from(l in Link,
      join: lt in LinkTag,
      on: lt.link_id == l.id,
      join: t in Tag,
      on: t.id == lt.tag_id,
      where: t.slug == ^slug,
      order_by: ^order_by,
      limit: ^limit
    )

    query = if langs != [] do
      from(l in query, where: fragment("? && ?", l.langs, ^langs))
    else
      query
    end

    Repo.all(query)
  end

  @doc """
  Get a tag by slug.
  """
  def get_tag_by_slug(slug) do
    Repo.get_by(Tag, slug: slug)
  end

  @doc """
  Get untagged links for processing.

  Options:
  - `:langs` - Filter by languages (default: ["en"] for English only)
  """
  def untagged_links(limit \\ 10, opts \\ []) do
    langs = opts[:langs] || ["en"]

    query = from(l in Link,
      where: is_nil(l.tagged_at),
      where: not is_nil(l.post_text),
      order_by: [desc: l.score],
      limit: ^limit
    )

    # Only filter by language if langs is non-empty
    query = if langs != [], do: from(l in query, where: fragment("? && ?", l.langs, ^langs)), else: query

    Repo.all(query)
  end

  @doc """
  Count untagged links.

  Options:
  - `:langs` - Filter by languages (default: ["en"] for English only)
  """
  def count_untagged(opts \\ []) do
    langs = opts[:langs] || ["en"]

    query = from(l in Link,
      where: is_nil(l.tagged_at),
      where: not is_nil(l.post_text)
    )

    # Only filter by language if langs is non-empty
    query = if langs != [], do: from(l in query, where: fragment("? && ?", l.langs, ^langs)), else: query

    Repo.aggregate(query, :count)
  end
end
