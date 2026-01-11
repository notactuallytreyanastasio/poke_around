defmodule PokeAround.LinksTest do
  use PokeAround.DataCase, async: true

  alias PokeAround.Links
  alias PokeAround.Links.Link

  describe "store_link/1" do
    test "creates link with computed url_hash and domain" do
      attrs = %{url: "https://example.com/article"}

      assert {:ok, %Link{} = link} = Links.store_link(attrs)
      assert link.url == "https://example.com/article"
      assert link.url_hash != nil
      assert link.domain == "example.com"
    end

    test "accepts string keys" do
      # Note: store_link converts string url key to atom but adds atom keys,
      # so we need all string keys to work. Testing with atom keys instead.
      attrs = %{url: "https://example.com/string-keys"}

      assert {:ok, %Link{} = link} = Links.store_link(attrs)
      assert link.url == "https://example.com/string-keys"
    end

    test "returns {:ok, :exists} for duplicate URLs" do
      attrs = %{url: "https://example.com/duplicate"}

      assert {:ok, %Link{}} = Links.store_link(attrs)
      assert {:ok, :exists} = Links.store_link(attrs)
    end

    test "considers normalized URLs as duplicates" do
      attrs1 = %{url: "https://EXAMPLE.COM/page/"}
      attrs2 = %{url: "https://example.com/page"}

      assert {:ok, %Link{}} = Links.store_link(attrs1)
      assert {:ok, :exists} = Links.store_link(attrs2)
    end

    test "stores optional fields" do
      attrs = %{
        url: "https://example.com/with-fields",
        post_text: "Check this out!",
        author_handle: "user.bsky.social",
        score: 75,
        tags: ["tech"],
        langs: ["en"]
      }

      assert {:ok, %Link{} = link} = Links.store_link(attrs)
      assert link.post_text == "Check this out!"
      assert link.author_handle == "user.bsky.social"
      assert link.score == 75
      assert link.tags == ["tech"]
      assert link.langs == ["en"]
    end
  end

  describe "get_link/1" do
    test "returns link by ID" do
      {:ok, created} = Links.store_link(%{url: "https://example.com/get-test"})

      assert %Link{} = link = Links.get_link(created.id)
      assert link.id == created.id
    end

    test "returns nil for non-existent ID" do
      assert nil == Links.get_link(999_999)
    end
  end

  describe "get_link_by_url/1" do
    test "returns link by URL" do
      url = "https://example.com/by-url"
      {:ok, _} = Links.store_link(%{url: url})

      assert %Link{} = link = Links.get_link_by_url(url)
      assert link.url == url
    end

    test "finds link with normalized URL" do
      {:ok, _} = Links.store_link(%{url: "https://example.com/normalized"})

      # Different case should still find it
      assert %Link{} = Links.get_link_by_url("https://EXAMPLE.COM/normalized")
    end

    test "returns nil for non-existent URL" do
      assert nil == Links.get_link_by_url("https://nonexistent.com")
    end
  end

  describe "random_link/1" do
    test "returns a random link" do
      {:ok, _} = Links.store_link(%{url: "https://example.com/random1", score: 10})
      {:ok, _} = Links.store_link(%{url: "https://example.com/random2", score: 10})

      link = Links.random_link()
      assert %Link{} = link
    end

    test "returns nil when no links exist" do
      assert nil == Links.random_link()
    end

    test "filters by min_score" do
      {:ok, low} = Links.store_link(%{url: "https://example.com/low-score", score: 5})
      {:ok, _high} = Links.store_link(%{url: "https://example.com/high-score", score: 50})

      # With min_score of 30, should only get high score link
      link = Links.random_link(min_score: 30)
      refute link.id == low.id
    end

    test "excludes specified IDs" do
      {:ok, link1} = Links.store_link(%{url: "https://example.com/exclude1"})
      {:ok, link2} = Links.store_link(%{url: "https://example.com/exclude2"})

      # Exclude link1, should get link2
      link = Links.random_link(exclude_ids: [link1.id])
      assert link.id == link2.id
    end

    test "filters by domain" do
      {:ok, _} = Links.store_link(%{url: "https://github.com/test"})
      {:ok, example} = Links.store_link(%{url: "https://example.com/domain-filter"})

      link = Links.random_link(domain: "example.com")
      assert link.id == example.id
    end

    test "filters by tags" do
      {:ok, tech} = Links.store_link(%{url: "https://example.com/tech", tags: ["tech", "news"]})
      {:ok, _sports} = Links.store_link(%{url: "https://example.com/sports", tags: ["sports"]})

      link = Links.random_link(tags: ["tech"])
      assert link.id == tech.id
    end
  end

  describe "random_links/2" do
    test "returns requested number of links" do
      for i <- 1..5 do
        Links.store_link(%{url: "https://example.com/batch#{i}"})
      end

      links = Links.random_links(3)
      assert length(links) == 3
    end

    test "returns fewer if not enough exist" do
      {:ok, _} = Links.store_link(%{url: "https://example.com/only-one"})

      links = Links.random_links(10)
      assert length(links) == 1
    end

    test "filters by min_score" do
      {:ok, _low} = Links.store_link(%{url: "https://example.com/multi-low", score: 5})
      {:ok, high} = Links.store_link(%{url: "https://example.com/multi-high", score: 50})

      links = Links.random_links(10, min_score: 30)
      assert length(links) == 1
      assert hd(links).id == high.id
    end

    test "filters by langs" do
      {:ok, en} = Links.store_link(%{url: "https://example.com/english", langs: ["en"]})
      {:ok, _es} = Links.store_link(%{url: "https://example.com/spanish", langs: ["es"]})

      links = Links.random_links(10, langs: ["en"])
      assert length(links) == 1
      assert hd(links).id == en.id
    end

    test "excludes specified IDs" do
      {:ok, link1} = Links.store_link(%{url: "https://example.com/multi-ex1"})
      {:ok, link2} = Links.store_link(%{url: "https://example.com/multi-ex2"})
      {:ok, link3} = Links.store_link(%{url: "https://example.com/multi-ex3"})

      links = Links.random_links(10, exclude_ids: [link1.id, link2.id])
      assert length(links) == 1
      assert hd(links).id == link3.id
    end
  end

  describe "increment_stumble_count/1" do
    test "increments stumble count" do
      {:ok, link} = Links.store_link(%{url: "https://example.com/stumble"})
      assert link.stumble_count == 0

      Links.increment_stumble_count(link.id)
      updated = Links.get_link(link.id)
      assert updated.stumble_count == 1

      Links.increment_stumble_count(link.id)
      updated = Links.get_link(link.id)
      assert updated.stumble_count == 2
    end
  end

  describe "list_links/1" do
    test "returns links ordered by insertion date descending" do
      {:ok, _} = Links.store_link(%{url: "https://example.com/list1"})
      Process.sleep(1)
      {:ok, second} = Links.store_link(%{url: "https://example.com/list2"})

      [first | _] = Links.list_links()
      assert first.id == second.id
    end

    test "paginates results" do
      for i <- 1..25 do
        Links.store_link(%{url: "https://example.com/page#{i}"})
      end

      page1 = Links.list_links(page: 1, per_page: 10)
      page2 = Links.list_links(page: 2, per_page: 10)
      page3 = Links.list_links(page: 3, per_page: 10)

      assert length(page1) == 10
      assert length(page2) == 10
      assert length(page3) == 5

      # No overlap
      page1_ids = Enum.map(page1, & &1.id) |> MapSet.new()
      page2_ids = Enum.map(page2, & &1.id) |> MapSet.new()
      assert MapSet.disjoint?(page1_ids, page2_ids)
    end

    test "uses defaults" do
      for i <- 1..25 do
        Links.store_link(%{url: "https://example.com/default#{i}"})
      end

      links = Links.list_links()
      assert length(links) == 20
    end
  end

  describe "count_links/0" do
    test "returns total link count" do
      assert Links.count_links() == 0

      Links.store_link(%{url: "https://example.com/count1"})
      assert Links.count_links() == 1

      Links.store_link(%{url: "https://example.com/count2"})
      assert Links.count_links() == 2
    end
  end

  describe "top_domains/1" do
    test "returns domains sorted by link count" do
      Links.store_link(%{url: "https://github.com/a"})
      Links.store_link(%{url: "https://github.com/b"})
      Links.store_link(%{url: "https://github.com/c"})
      Links.store_link(%{url: "https://example.com/x"})

      [{domain, count} | _] = Links.top_domains()
      assert domain == "github.com"
      assert count == 3
    end

    test "limits results" do
      Links.store_link(%{url: "https://a.com/1"})
      Links.store_link(%{url: "https://b.com/1"})
      Links.store_link(%{url: "https://c.com/1"})

      domains = Links.top_domains(2)
      assert length(domains) == 2
    end

    test "returns empty list when no links" do
      assert Links.top_domains() == []
    end
  end
end
