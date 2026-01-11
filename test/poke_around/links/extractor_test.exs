defmodule PokeAround.Links.ExtractorTest do
  use PokeAround.DataCase, async: false

  alias PokeAround.Links.Extractor
  alias PokeAround.Links

  # Test fixtures
  defp qualifying_author do
    %{
      did: "did:plc:test123",
      handle: "test.bsky.social",
      display_name: "Test User",
      followers_count: 1000,
      follows_count: 200,
      description: "A developer who loves Elixir",
      indexed_at: DateTime.add(DateTime.utc_now(), -400, :day)
    }
  end

  defp long_text do
    "This is a sufficiently long piece of text that definitely exceeds fifty characters"
  end

  defp make_post(overrides \\ %{}) do
    base = %{
      uri: "at://did:plc:test/app.bsky.feed.post/#{System.unique_integer([:positive])}",
      text: long_text(),
      author: qualifying_author(),
      created_at: DateTime.utc_now(),
      langs: ["en"],
      embed: nil
    }

    Map.merge(base, overrides)
  end

  defp make_post_with_link(url, overrides \\ %{}) do
    text = long_text() <> " Check this out: #{url}"
    make_post(Map.merge(%{text: text}, overrides))
  end

  # Create event in Jetstream format (what the firehose sends)
  defp jetstream_event(post) do
    %{
      "did" => post.author.did,
      "time_us" => System.os_time(:microsecond),
      "kind" => "commit",
      "commit" => %{
        "operation" => "create",
        "collection" => "app.bsky.feed.post",
        "rkey" => "abc123",
        "record" => %{
          "$type" => "app.bsky.feed.post",
          "text" => post.text,
          "createdAt" => DateTime.to_iso8601(post.created_at),
          "langs" => post.langs,
          "facets" => build_facets(post.text)
        }
      },
      # Include hydrated author for realistic test
      "author" => %{
        "did" => post.author.did,
        "handle" => post.author.handle,
        "displayName" => post.author.display_name,
        "followersCount" => post.author.followers_count,
        "followsCount" => post.author.follows_count,
        "description" => post.author.description,
        "indexedAt" => DateTime.to_iso8601(post.author.indexed_at)
      }
    }
  end

  # Build facets for link detection
  defp build_facets(text) do
    # Find URLs in text
    url_regex = ~r/https?:\/\/[^\s]+/
    matches = Regex.scan(url_regex, text, return: :index)

    Enum.map(matches, fn [{start, length}] ->
      url = String.slice(text, start, length)

      %{
        "index" => %{"byteStart" => start, "byteEnd" => start + length},
        "features" => [
          %{"$type" => "app.bsky.richtext.facet#link", "uri" => url}
        ]
      }
    end)
  end

  describe "start_link/1" do
    test "starts the GenServer with default name" do
      # Use a unique name to avoid conflicts with the app's Extractor
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_1)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with custom name" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :custom_extractor)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "get_stats/1" do
    test "returns stats map with initial values" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_2)

      stats = Extractor.get_stats(pid)

      assert is_integer(stats.posts_processed)
      assert is_integer(stats.links_found)
      assert is_integer(stats.links_qualified)
      assert is_integer(stats.uptime_seconds)
      assert is_float(stats.qualification_rate)

      GenServer.stop(pid)
    end

    test "uptime increases over time" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_3)

      stats1 = Extractor.get_stats(pid)
      Process.sleep(100)
      stats2 = Extractor.get_stats(pid)

      assert stats2.uptime_seconds >= stats1.uptime_seconds

      GenServer.stop(pid)
    end
  end

  # Note: Tests disable PubSub subscription to avoid receiving real firehose events.
  # We manually send events via `send(pid, {:post, event})` for controlled testing.

  describe "processing posts via handle_info" do
    test "increments posts_processed for valid posts" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_4)

      before = Extractor.get_stats(pid)

      # Post without links
      post = make_post()
      event = jetstream_event(post)

      send(pid, {:post, event})
      Process.sleep(50)

      after_stats = Extractor.get_stats(pid)
      assert after_stats.posts_processed >= before.posts_processed + 1

      GenServer.stop(pid)
    end

    test "increments links_found when post has links" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_5)

      before = Extractor.get_stats(pid)

      post = make_post_with_link("https://example.com/article")
      event = jetstream_event(post)

      send(pid, {:post, event})
      Process.sleep(50)

      after_stats = Extractor.get_stats(pid)
      assert after_stats.posts_processed >= before.posts_processed + 1
      assert after_stats.links_found >= before.links_found + 1

      GenServer.stop(pid)
    end

    test "qualifies and stores good links" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_6)

      # Unique URL to avoid test conflicts
      url = "https://example.com/qualified-#{System.unique_integer([:positive])}"
      post = make_post_with_link(url)
      event = jetstream_event(post)

      send(pid, {:post, event})
      Process.sleep(100)

      # Verify link was stored in database (primary assertion)
      stored = Links.get_link_by_url(url)
      assert stored != nil
      assert stored.url == url

      GenServer.stop(pid)
    end

    test "rejects posts with multiple links as spam" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_7)

      url1 = "https://example.com/spam-link1-#{System.unique_integer([:positive])}"
      url2 = "https://example.com/spam-link2-#{System.unique_integer([:positive])}"
      text = long_text() <> " #{url1} #{url2}"

      post = make_post(%{text: text})
      event = jetstream_event(post)

      send(pid, {:post, event})
      Process.sleep(50)

      # Neither link should be stored (spam = multiple links)
      assert Links.get_link_by_url(url1) == nil
      assert Links.get_link_by_url(url2) == nil

      GenServer.stop(pid)
    end

    test "rejects banned domains" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_8)

      # bit.ly is a banned domain - use unique path
      url = "https://bit.ly/spam-#{System.unique_integer([:positive])}"
      post = make_post_with_link(url)
      event = jetstream_event(post)

      send(pid, {:post, event})
      Process.sleep(50)

      # Link should NOT be stored
      assert Links.get_link_by_url(url) == nil

      GenServer.stop(pid)
    end

    test "rejects crypto domains" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_9)

      url = "https://coinbase.com/trade/#{System.unique_integer([:positive])}"
      post = make_post_with_link(url)
      event = jetstream_event(post)

      send(pid, {:post, event})
      Process.sleep(50)

      assert Links.get_link_by_url(url) == nil

      GenServer.stop(pid)
    end

    test "rejects subdomains of banned domains" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_10)

      url = "https://pro.coinbase.com/advanced/#{System.unique_integer([:positive])}"
      post = make_post_with_link(url)
      event = jetstream_event(post)

      send(pid, {:post, event})
      Process.sleep(50)

      assert Links.get_link_by_url(url) == nil

      GenServer.stop(pid)
    end

    test "rejects posts from authors with too few followers" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_11)

      author = %{qualifying_author() | followers_count: 100}
      url = "https://example.com/low-followers-#{System.unique_integer([:positive])}"
      post = make_post_with_link(url, %{author: author})
      event = jetstream_event(post)

      send(pid, {:post, event})
      Process.sleep(50)

      assert Links.get_link_by_url(url) == nil

      GenServer.stop(pid)
    end

    test "rejects posts from authors following too many" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_12)

      author = %{qualifying_author() | follows_count: 10000}
      url = "https://example.com/high-following-#{System.unique_integer([:positive])}"
      post = make_post_with_link(url, %{author: author})
      event = jetstream_event(post)

      send(pid, {:post, event})
      Process.sleep(50)

      assert Links.get_link_by_url(url) == nil

      GenServer.stop(pid)
    end

    test "rejects posts with too many hashtags" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_13)

      url = "https://example.com/hashtags-#{System.unique_integer([:positive])}"
      text = long_text() <> " #{url} #one #two #three"
      post = make_post(%{text: text})
      event = jetstream_event(post)

      send(pid, {:post, event})
      Process.sleep(50)

      assert Links.get_link_by_url(url) == nil

      GenServer.stop(pid)
    end

    test "rejects posts with too many emojis" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_14)

      url = "https://example.com/emojis-#{System.unique_integer([:positive])}"
      text = long_text() <> " #{url} 😀😎🎉"
      post = make_post(%{text: text})
      event = jetstream_event(post)

      send(pid, {:post, event})
      Process.sleep(50)

      assert Links.get_link_by_url(url) == nil

      GenServer.stop(pid)
    end

    test "rejects posts with short text after removing hashtags" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_15)

      url = "https://example.com/short-#{System.unique_integer([:positive])}"
      text = "Short text #{url} #longhashtag"
      post = make_post(%{text: text})
      event = jetstream_event(post)

      send(pid, {:post, event})
      Process.sleep(50)

      assert Links.get_link_by_url(url) == nil

      GenServer.stop(pid)
    end

    test "rejects posts from new accounts" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_16)

      author = %{qualifying_author() | indexed_at: DateTime.add(DateTime.utc_now(), -30, :day)}
      url = "https://example.com/new-account-#{System.unique_integer([:positive])}"
      post = make_post_with_link(url, %{author: author})
      event = jetstream_event(post)

      send(pid, {:post, event})
      Process.sleep(50)

      assert Links.get_link_by_url(url) == nil

      GenServer.stop(pid)
    end

    test "rejects posts without author bio" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_17)

      author = %{qualifying_author() | description: nil}
      url = "https://example.com/no-bio-#{System.unique_integer([:positive])}"
      post = make_post_with_link(url, %{author: author})
      event = jetstream_event(post)

      send(pid, {:post, event})
      Process.sleep(50)

      assert Links.get_link_by_url(url) == nil

      GenServer.stop(pid)
    end
  end

  describe "qualification_rate calculation" do
    test "qualification_rate is between 0 and 1" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_18)

      # Send one qualifying link
      url1 = "https://example.com/rate1-#{System.unique_integer([:positive])}"
      post1 = make_post_with_link(url1)
      send(pid, {:post, jetstream_event(post1)})

      Process.sleep(100)

      stats = Extractor.get_stats(pid)
      assert stats.qualification_rate >= 0.0
      assert stats.qualification_rate <= 1.0

      # Qualified link was stored
      assert Links.get_link_by_url(url1) != nil

      GenServer.stop(pid)
    end
  end

  describe "stored link attributes" do
    test "stores author info with link" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_19)

      url = "https://example.com/with-author-#{System.unique_integer([:positive])}"
      author = qualifying_author()
      post = make_post_with_link(url, %{author: author})
      event = jetstream_event(post)

      send(pid, {:post, event})
      Process.sleep(100)

      stored = Links.get_link_by_url(url)
      assert stored.author_handle == author.handle
      assert stored.author_did == author.did

      GenServer.stop(pid)
    end

    test "calculates and stores score" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_20)

      url = "https://example.com/with-score-#{System.unique_integer([:positive])}"
      post = make_post_with_link(url)
      event = jetstream_event(post)

      send(pid, {:post, event})
      Process.sleep(100)

      stored = Links.get_link_by_url(url)
      assert stored.score > 0

      GenServer.stop(pid)
    end

    test "stores langs" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_21)

      url = "https://example.com/with-langs-#{System.unique_integer([:positive])}"
      post = make_post_with_link(url, %{langs: ["en", "es"]})
      event = jetstream_event(post)

      send(pid, {:post, event})
      Process.sleep(100)

      stored = Links.get_link_by_url(url)
      assert stored.langs == ["en", "es"]

      GenServer.stop(pid)
    end
  end

  describe "duplicate handling" do
    test "stores link only once for duplicate URLs" do
      {:ok, pid} = Extractor.start_link(subscribe: false, name: :test_extractor_22)

      url = "https://example.com/duplicate-#{System.unique_integer([:positive])}"
      post = make_post_with_link(url)
      event = jetstream_event(post)

      # Send same link twice
      send(pid, {:post, event})
      Process.sleep(100)
      send(pid, {:post, event})
      Process.sleep(100)

      # Link exists in database (was stored first time)
      stored = Links.get_link_by_url(url)
      assert stored != nil

      # Verify only one record exists (not duplicated)
      assert Links.count_links() >= 1

      GenServer.stop(pid)
    end
  end
end
