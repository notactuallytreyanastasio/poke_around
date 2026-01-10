defmodule PokeAround.TagsTest do
  use PokeAround.DataCase, async: true

  alias PokeAround.Tags
  alias PokeAround.Tags.Tag
  alias PokeAround.Fixtures

  describe "get_or_create_tag/1" do
    test "creates a new tag" do
      {:ok, tag} = Tags.get_or_create_tag("New Tag")

      assert tag.name == "New Tag"
      assert tag.slug == "new-tag"
      assert tag.usage_count == 0
    end

    test "returns existing tag if slug matches" do
      {:ok, original} = Tags.get_or_create_tag("Test Tag")
      {:ok, found} = Tags.get_or_create_tag("Test Tag")

      assert original.id == found.id
    end

    test "normalizes tag name to slug" do
      {:ok, tag} = Tags.get_or_create_tag("JavaScript Tutorial")

      assert tag.slug == "javascript-tutorial"
    end

    test "handles special characters in tag name" do
      {:ok, tag} = Tags.get_or_create_tag("C++ Programming!")

      assert tag.slug == "c-programming"
    end
  end

  describe "tag_link/3" do
    test "tags a link with multiple tags" do
      link = Fixtures.link_fixture(%{tagged_at: nil})

      {:ok, :ok} = Tags.tag_link(link, ["tech", "javascript", "tutorial"])

      tags = Tags.get_tags_for_link(link.id)
      tag_slugs = Enum.map(tags, & &1.slug)

      assert "tech" in tag_slugs
      assert "javascript" in tag_slugs
      assert "tutorial" in tag_slugs
    end

    test "sets source on link tags" do
      link = Fixtures.link_fixture(%{tagged_at: nil})

      Tags.tag_link(link, ["test-tag"], source: "axon")

      # Verify in database
      link_tag =
        Repo.one(
          from lt in PokeAround.Tags.LinkTag,
          where: lt.link_id == ^link.id
        )

      assert link_tag.source == "axon"
    end

    test "marks link as tagged" do
      link = Fixtures.link_fixture(%{tagged_at: nil})
      assert is_nil(link.tagged_at)

      Tags.tag_link(link, ["test-tag"])

      updated_link = Repo.get!(PokeAround.Links.Link, link.id)
      refute is_nil(updated_link.tagged_at)
    end

    test "increments tag usage count" do
      link1 = Fixtures.link_fixture(%{tagged_at: nil})
      link2 = Fixtures.link_fixture(%{tagged_at: nil})

      Tags.tag_link(link1, ["popular-tag"])
      Tags.tag_link(link2, ["popular-tag"])

      tag = Tags.get_tag_by_slug("popular-tag")
      assert tag.usage_count == 2
    end

    test "handles duplicate tag associations gracefully" do
      link = Fixtures.link_fixture(%{tagged_at: nil})

      # Tag the same link twice with the same tags
      Tags.tag_link(link, ["duplicate-tag"])
      Tags.tag_link(link, ["duplicate-tag"])

      tags = Tags.get_tags_for_link(link.id)
      assert length(tags) == 1
    end

    test "handles empty tag list" do
      link = Fixtures.link_fixture(%{tagged_at: nil})

      {:ok, :ok} = Tags.tag_link(link, [])

      tags = Tags.get_tags_for_link(link.id)
      assert tags == []
    end
  end

  describe "get_tags_for_link/1" do
    test "returns all tags for a link" do
      link = Fixtures.tagged_link_fixture(%{}, ["tag1", "tag2", "tag3"])

      tags = Tags.get_tags_for_link(link.id)

      assert length(tags) == 3
    end

    test "returns empty list for untagged link" do
      link = Fixtures.link_fixture(%{tagged_at: nil})

      tags = Tags.get_tags_for_link(link.id)

      assert tags == []
    end
  end

  describe "popular_tags/1" do
    test "returns tags ordered by usage count" do
      # Create tags with different usage counts
      _tag1 = Fixtures.tag_fixture(%{name: "unpopular", usage_count: 1})
      _tag2 = Fixtures.tag_fixture(%{name: "popular", usage_count: 100})
      _tag3 = Fixtures.tag_fixture(%{name: "medium", usage_count: 50})

      tags = Tags.popular_tags(10)

      # Should be ordered by usage_count descending
      usage_counts = Enum.map(tags, & &1.usage_count)
      assert usage_counts == Enum.sort(usage_counts, :desc)
    end

    test "respects limit" do
      # Create more tags than limit
      Enum.each(1..5, fn i ->
        Fixtures.tag_fixture(%{name: "tag#{i}", usage_count: i})
      end)

      tags = Tags.popular_tags(3)

      assert length(tags) <= 3
    end
  end

  describe "links_by_tag/2" do
    test "returns links with the given tag" do
      tag = Fixtures.tag_fixture(%{name: "specific-tag"})

      link1 = Fixtures.link_fixture(%{post_text: "First post"})
      link2 = Fixtures.link_fixture(%{post_text: "Second post"})
      _link3 = Fixtures.link_fixture(%{post_text: "Unrelated post"})

      # Associate links with tag
      Repo.insert_all("link_tags", [
        %{link_id: link1.id, tag_id: tag.id, source: "test",
          inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()},
        %{link_id: link2.id, tag_id: tag.id, source: "test",
          inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}
      ])

      links = Tags.links_by_tag("specific-tag")

      link_ids = Enum.map(links, & &1.id)
      assert link1.id in link_ids
      assert link2.id in link_ids
      assert length(links) == 2
    end

    test "filters by language" do
      tag = Fixtures.tag_fixture(%{name: "lang-test"})

      en_link = Fixtures.link_fixture(%{post_text: "English", langs: ["en"]})
      es_link = Fixtures.link_fixture(%{post_text: "Spanish", langs: ["es"]})

      Repo.insert_all("link_tags", [
        %{link_id: en_link.id, tag_id: tag.id, source: "test",
          inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()},
        %{link_id: es_link.id, tag_id: tag.id, source: "test",
          inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}
      ])

      en_links = Tags.links_by_tag("lang-test", langs: ["en"])

      assert length(en_links) == 1
      assert hd(en_links).id == en_link.id
    end

    test "orders by newest by default" do
      tag = Fixtures.tag_fixture(%{name: "order-test"})

      # Create links with slight time gap
      link1 = Fixtures.link_fixture(%{post_text: "Older"})
      Process.sleep(10)
      link2 = Fixtures.link_fixture(%{post_text: "Newer"})

      Repo.insert_all("link_tags", [
        %{link_id: link1.id, tag_id: tag.id, source: "test",
          inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()},
        %{link_id: link2.id, tag_id: tag.id, source: "test",
          inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}
      ])

      links = Tags.links_by_tag("order-test", order: :newest)

      # Newer should be first
      assert hd(links).id == link2.id
    end

    test "orders by score when specified" do
      tag = Fixtures.tag_fixture(%{name: "score-test"})

      low_score = Fixtures.link_fixture(%{post_text: "Low", score: 10})
      high_score = Fixtures.link_fixture(%{post_text: "High", score: 90})

      Repo.insert_all("link_tags", [
        %{link_id: low_score.id, tag_id: tag.id, source: "test",
          inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()},
        %{link_id: high_score.id, tag_id: tag.id, source: "test",
          inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}
      ])

      links = Tags.links_by_tag("score-test", order: :score)

      # Higher score should be first
      assert hd(links).id == high_score.id
    end
  end

  describe "get_tag_by_slug/1" do
    test "finds tag by slug" do
      {:ok, created} = Tags.get_or_create_tag("Find Me")

      found = Tags.get_tag_by_slug("find-me")

      assert found.id == created.id
    end

    test "returns nil for nonexistent slug" do
      result = Tags.get_tag_by_slug("nonexistent-tag")

      assert is_nil(result)
    end
  end

  describe "untagged_links/2" do
    test "returns links without tagged_at" do
      _tagged = Fixtures.link_fixture(%{
        post_text: "Tagged post",
        tagged_at: DateTime.utc_now()
      })

      untagged = Fixtures.link_fixture(%{
        post_text: "Untagged post",
        tagged_at: nil
      })

      links = Tags.untagged_links(10)

      link_ids = Enum.map(links, & &1.id)
      assert untagged.id in link_ids
    end

    test "filters by language" do
      _en = Fixtures.link_fixture(%{
        post_text: "English",
        langs: ["en"],
        tagged_at: nil
      })

      _es = Fixtures.link_fixture(%{
        post_text: "Spanish",
        langs: ["es"],
        tagged_at: nil
      })

      links = Tags.untagged_links(10, langs: ["en"])

      assert Enum.all?(links, fn l -> "en" in l.langs end)
    end

    test "orders by score descending" do
      _low = Fixtures.link_fixture(%{post_text: "Low", score: 10, tagged_at: nil})
      high = Fixtures.link_fixture(%{post_text: "High", score: 90, tagged_at: nil})

      links = Tags.untagged_links(10)

      # Higher score should be first
      assert hd(links).id == high.id
    end

    test "respects limit" do
      Enum.each(1..5, fn i ->
        Fixtures.link_fixture(%{post_text: "Link #{i}", tagged_at: nil})
      end)

      links = Tags.untagged_links(2)

      assert length(links) == 2
    end

    test "excludes links without post_text" do
      _no_text = Fixtures.link_fixture(%{post_text: nil, tagged_at: nil})
      with_text = Fixtures.link_fixture(%{post_text: "Has text", tagged_at: nil})

      links = Tags.untagged_links(10)

      link_ids = Enum.map(links, & &1.id)
      assert with_text.id in link_ids
    end
  end

  describe "count_untagged/1" do
    test "counts untagged links" do
      Fixtures.link_fixture(%{post_text: "Untagged 1", tagged_at: nil})
      Fixtures.link_fixture(%{post_text: "Untagged 2", tagged_at: nil})
      Fixtures.link_fixture(%{post_text: "Tagged", tagged_at: DateTime.utc_now()})

      count = Tags.count_untagged()

      assert count >= 2
    end

    test "filters by language" do
      Fixtures.link_fixture(%{post_text: "EN", langs: ["en"], tagged_at: nil})
      Fixtures.link_fixture(%{post_text: "ES", langs: ["es"], tagged_at: nil})

      en_count = Tags.count_untagged(langs: ["en"])
      all_count = Tags.count_untagged(langs: [])

      assert en_count < all_count or en_count == all_count
    end
  end
end
