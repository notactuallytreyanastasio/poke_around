defmodule PokeAround.ATProto.Lexicon do
  @moduledoc """
  Elixir struct definitions for space.pokearound.* lexicon records.

  These structs map to the JSON schemas defined in priv/lexicons/
  and provide helpers for converting between database schemas and
  ATProto record format.
  """

  alias PokeAround.Links.Link

  defmodule SourcePost do
    @moduledoc "Metadata about the source Bluesky post"

    defstruct [:uri, :author_did, :author_handle, :text, :posted_at]

    @type t :: %__MODULE__{
            uri: String.t() | nil,
            author_did: String.t() | nil,
            author_handle: String.t() | nil,
            text: String.t() | nil,
            posted_at: DateTime.t() | nil
          }

    def to_record(%__MODULE__{} = source) do
      %{
        "uri" => source.uri,
        "authorDid" => source.author_did,
        "authorHandle" => source.author_handle,
        "text" => truncate(source.text, 500),
        "postedAt" => format_datetime(source.posted_at)
      }
      |> reject_nils()
    end

    defp truncate(nil, _), do: nil
    defp truncate(str, max) when byte_size(str) <= max, do: str
    defp truncate(str, max), do: String.slice(str, 0, max - 3) <> "..."

    defp format_datetime(nil), do: nil
    defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

    defp reject_nils(map), do: Map.reject(map, fn {_k, v} -> is_nil(v) end)
  end

  defmodule LinkRecord do
    @moduledoc """
    space.pokearound.link record structure.

    A curated link from the PokeAround discovery service.
    """

    defstruct [
      :url,
      :title,
      :description,
      :domain,
      :image_url,
      :tags,
      :langs,
      :score,
      :source_post,
      :created_at
    ]

    @type t :: %__MODULE__{
            url: String.t(),
            title: String.t() | nil,
            description: String.t() | nil,
            domain: String.t() | nil,
            image_url: String.t() | nil,
            tags: [String.t()],
            langs: [String.t()],
            score: integer() | nil,
            source_post: SourcePost.t() | nil,
            created_at: DateTime.t()
          }

    @doc """
    Convert a database Link to a LinkRecord struct.
    """
    def from_db(%Link{} = link) do
      %__MODULE__{
        url: link.url,
        title: link.title,
        description: link.description,
        domain: link.domain,
        image_url: link.image_url,
        tags: link.tags || [],
        langs: link.langs || [],
        score: link.score,
        source_post: %SourcePost{
          uri: link.post_uri,
          author_did: link.author_did,
          author_handle: link.author_handle,
          text: link.post_text,
          posted_at: link.post_created_at
        },
        created_at: link.inserted_at
      }
    end

    @doc """
    Convert to ATProto record format (for PDS storage).
    """
    def to_record(%__MODULE__{} = link) do
      record = %{
        "$type" => "space.pokearound.link",
        "url" => link.url,
        "createdAt" => DateTime.to_iso8601(link.created_at)
      }

      record
      |> maybe_put("title", truncate(link.title, 500))
      |> maybe_put("description", truncate(link.description, 2000))
      |> maybe_put("domain", link.domain)
      |> maybe_put("imageUrl", link.image_url)
      |> maybe_put("tags", non_empty_list(link.tags, 10))
      |> maybe_put("langs", non_empty_list(link.langs, 5))
      |> maybe_put("score", link.score)
      |> maybe_put_nested("sourcePost", link.source_post, &SourcePost.to_record/1)
    end

    defp maybe_put(map, _key, nil), do: map
    defp maybe_put(map, _key, ""), do: map
    defp maybe_put(map, key, value), do: Map.put(map, key, value)

    defp maybe_put_nested(map, _key, nil, _fun), do: map

    defp maybe_put_nested(map, key, value, fun) do
      nested = fun.(value)

      if map_size(nested) > 0 do
        Map.put(map, key, nested)
      else
        map
      end
    end

    defp truncate(nil, _), do: nil
    defp truncate(str, max) when byte_size(str) <= max, do: str
    defp truncate(str, max), do: String.slice(str, 0, max - 3) <> "..."

    defp non_empty_list(nil, _max), do: nil
    defp non_empty_list([], _max), do: nil
    defp non_empty_list(list, max), do: Enum.take(list, max)
  end

  defmodule BookmarkRecord do
    @moduledoc """
    space.pokearound.bookmark record structure.

    A personal bookmark saved to user's PDS.
    """

    defstruct [
      :url,
      :title,
      :domain,
      :note,
      :personal_tags,
      :poke_around_uri,
      :created_at
    ]

    @type t :: %__MODULE__{
            url: String.t(),
            title: String.t() | nil,
            domain: String.t() | nil,
            note: String.t() | nil,
            personal_tags: [String.t()],
            poke_around_uri: String.t() | nil,
            created_at: DateTime.t()
          }

    @doc """
    Create a new bookmark from a Link.
    """
    def from_link(%Link{} = link, opts \\ []) do
      %__MODULE__{
        url: link.url,
        title: link.title,
        domain: link.domain,
        note: opts[:note],
        personal_tags: opts[:tags] || [],
        poke_around_uri: link.at_uri,
        created_at: DateTime.utc_now()
      }
    end

    @doc """
    Convert to ATProto record format.
    """
    def to_record(%__MODULE__{} = bookmark) do
      record = %{
        "$type" => "space.pokearound.bookmark",
        "url" => bookmark.url,
        "createdAt" => DateTime.to_iso8601(bookmark.created_at)
      }

      record
      |> maybe_put("title", truncate(bookmark.title, 500))
      |> maybe_put("domain", bookmark.domain)
      |> maybe_put("note", truncate(bookmark.note, 1000))
      |> maybe_put("personalTags", non_empty_list(bookmark.personal_tags, 10))
      |> maybe_put("pokeAroundUri", bookmark.poke_around_uri)
    end

    defp maybe_put(map, _key, nil), do: map
    defp maybe_put(map, _key, ""), do: map
    defp maybe_put(map, key, value), do: Map.put(map, key, value)

    defp truncate(nil, _), do: nil
    defp truncate(str, max) when byte_size(str) <= max, do: str
    defp truncate(str, max), do: String.slice(str, 0, max - 3) <> "..."

    defp non_empty_list(nil, _max), do: nil
    defp non_empty_list([], _max), do: nil
    defp non_empty_list(list, max), do: Enum.take(list, max)
  end
end
