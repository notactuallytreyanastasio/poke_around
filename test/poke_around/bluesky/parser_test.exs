defmodule PokeAround.Bluesky.ParserTest do
  use ExUnit.Case, async: true

  alias PokeAround.Bluesky.Parser
  alias PokeAround.Bluesky.Types.{Post, ExternalEmbed, FacetLink}

  describe "parse_post/1 with Turbostream format" do
    test "parses valid turbostream event" do
      event = turbostream_event()

      assert {:ok, %Post{} = post} = Parser.parse_post(event)
      assert post.uri == "at://did:plc:abc123/app.bsky.feed.post/xyz"
      assert post.text == "Check out this article!"
      assert post.author.did == "did:plc:abc123"
      assert post.author.handle == "user.bsky.social"
      assert post.author.followers_count == 1000
    end

    test "parses author metadata from turbostream" do
      event = turbostream_event()

      {:ok, post} = Parser.parse_post(event)

      assert post.author.display_name == "Test User"
      assert post.author.description == "A test user"
      assert post.author.follows_count == 200
      assert post.author.posts_count == 500
    end

    test "parses created_at datetime" do
      event = turbostream_event()

      {:ok, post} = Parser.parse_post(event)

      assert %DateTime{} = post.created_at
      assert post.created_at.year == 2024
    end

    test "parses external embed" do
      event =
        turbostream_event()
        |> put_in(["message", "commit", "record", "embed"], %{
          "$type" => "app.bsky.embed.external",
          "external" => %{
            "uri" => "https://example.com/article",
            "title" => "Article Title",
            "description" => "Article description"
          }
        })

      {:ok, post} = Parser.parse_post(event)

      assert %ExternalEmbed{} = post.external_embed
      assert post.external_embed.uri == "https://example.com/article"
      assert post.external_embed.title == "Article Title"
    end

    test "parses facet links" do
      event =
        turbostream_event()
        |> put_in(["message", "commit", "record", "facets"], [
          %{
            "index" => %{"byteStart" => 10, "byteEnd" => 30},
            "features" => [
              %{"$type" => "app.bsky.richtext.facet#link", "uri" => "https://example.com"}
            ]
          }
        ])

      {:ok, post} = Parser.parse_post(event)

      assert [%FacetLink{} = link] = post.facet_links
      assert link.uri == "https://example.com"
      assert link.byte_start == 10
      assert link.byte_end == 30
    end

    test "parses langs array" do
      event =
        turbostream_event()
        |> put_in(["message", "commit", "record", "langs"], ["en", "es"])

      {:ok, post} = Parser.parse_post(event)

      assert post.langs == ["en", "es"]
    end

    test "detects reply posts" do
      event =
        turbostream_event()
        |> put_in(["message", "commit", "record", "reply"], %{
          "parent" => %{"uri" => "at://did:plc:parent/app.bsky.feed.post/abc"}
        })

      {:ok, post} = Parser.parse_post(event)

      assert post.is_reply == true
      assert post.reply_to == "at://did:plc:parent/app.bsky.feed.post/abc"
    end

    test "handles missing author in metadata" do
      event =
        turbostream_event()
        |> Map.put("hydrated_metadata", %{})

      {:ok, post} = Parser.parse_post(event)

      assert post.author == nil
    end
  end

  describe "parse_post/1 with Jetstream format" do
    test "parses valid jetstream event" do
      event = jetstream_event()

      assert {:ok, %Post{} = post} = Parser.parse_post(event)
      assert post.uri == "at://did:plc:jet123/app.bsky.feed.post/rkey456"
      assert post.text == "Jetstream post"
    end

    test "constructs URI from did and rkey" do
      event = jetstream_event()

      {:ok, post} = Parser.parse_post(event)

      assert post.uri =~ "did:plc:jet123"
      assert post.uri =~ "rkey456"
    end
  end

  describe "parse_post/1 error handling" do
    test "returns error for invalid event structure" do
      assert {:error, :invalid_event} = Parser.parse_post(%{})
    end

    test "returns error for nil input" do
      assert {:error, :invalid_event} = Parser.parse_post(nil)
    end

    test "returns error for non-map input" do
      assert {:error, :invalid_event} = Parser.parse_post("not a map")
    end
  end

  describe "extract_links/1" do
    test "extracts link from external embed" do
      post = %Post{
        uri: "at://test",
        text: "text",
        external_embed: %ExternalEmbed{uri: "https://example.com/article"},
        facet_links: []
      }

      assert ["https://example.com/article"] = Parser.extract_links(post)
    end

    test "extracts links from facets" do
      post = %Post{
        uri: "at://test",
        text: "text",
        external_embed: nil,
        facet_links: [
          %FacetLink{uri: "https://example.com/a"},
          %FacetLink{uri: "https://example.com/b"}
        ]
      }

      links = Parser.extract_links(post)
      assert "https://example.com/a" in links
      assert "https://example.com/b" in links
    end

    test "combines embed and facet links" do
      post = %Post{
        uri: "at://test",
        text: "text",
        external_embed: %ExternalEmbed{uri: "https://example.com/embed"},
        facet_links: [%FacetLink{uri: "https://example.com/facet"}]
      }

      links = Parser.extract_links(post)
      assert length(links) == 2
      assert "https://example.com/embed" in links
      assert "https://example.com/facet" in links
    end

    test "deduplicates links" do
      post = %Post{
        uri: "at://test",
        text: "text",
        external_embed: %ExternalEmbed{uri: "https://example.com"},
        facet_links: [%FacetLink{uri: "https://example.com"}]
      }

      links = Parser.extract_links(post)
      assert links == ["https://example.com"]
    end

    test "filters out bsky.app links" do
      post = %Post{
        uri: "at://test",
        text: "text",
        external_embed: nil,
        facet_links: [
          %FacetLink{uri: "https://bsky.app/profile/user"},
          %FacetLink{uri: "https://example.com"}
        ]
      }

      links = Parser.extract_links(post)
      assert links == ["https://example.com"]
    end

    test "filters out bsky.social links" do
      post = %Post{
        uri: "at://test",
        text: "text",
        external_embed: nil,
        facet_links: [%FacetLink{uri: "https://bsky.social/something"}]
      }

      assert Parser.extract_links(post) == []
    end

    test "filters out at:// URIs" do
      post = %Post{
        uri: "at://test",
        text: "text",
        external_embed: nil,
        facet_links: [%FacetLink{uri: "at://did:plc:abc/app.bsky.feed.post/xyz"}]
      }

      assert Parser.extract_links(post) == []
    end

    test "returns empty list when no links" do
      post = %Post{
        uri: "at://test",
        text: "text",
        external_embed: nil,
        facet_links: []
      }

      assert Parser.extract_links(post) == []
    end

    test "handles nil facet_links" do
      post = %Post{
        uri: "at://test",
        text: "text",
        external_embed: nil,
        facet_links: nil
      }

      assert Parser.extract_links(post) == []
    end
  end

  # Test fixtures

  defp turbostream_event do
    %{
      "at_uri" => "at://did:plc:abc123/app.bsky.feed.post/xyz",
      "message" => %{
        "commit" => %{
          "cid" => "bafyreiabc123",
          "record" => %{
            "text" => "Check out this article!",
            "createdAt" => "2024-01-15T10:30:00.000Z"
          }
        }
      },
      "hydrated_metadata" => %{
        "user" => %{
          "did" => "did:plc:abc123",
          "handle" => "user.bsky.social",
          "display_name" => "Test User",
          "description" => "A test user",
          "followers_count" => 1000,
          "follows_count" => 200,
          "posts_count" => 500,
          "indexed_at" => "2023-01-01T00:00:00.000Z"
        }
      }
    }
  end

  defp jetstream_event do
    %{
      "did" => "did:plc:jet123",
      "commit" => %{
        "rkey" => "rkey456",
        "cid" => "bafyreicid",
        "record" => %{
          "text" => "Jetstream post",
          "createdAt" => "2024-01-15T12:00:00.000Z"
        }
      }
    }
  end
end
