defmodule PokeAround.Links.QualityFilterTest do
  use ExUnit.Case, async: true

  alias PokeAround.Links.QualityFilter

  describe "qualifies?/1" do
    test "returns false when author is nil" do
      refute QualityFilter.qualifies?(%{author: nil, text: "Some text"})
    end

    test "returns true for qualifying post and author" do
      post = qualifying_post()
      assert QualityFilter.qualifies?(post)
    end

    test "returns false when author doesn't qualify" do
      post = %{
        author: %{
          followers_count: 100,
          follows_count: 100,
          description: "Bio",
          indexed_at: old_date()
        },
        text: long_text()
      }

      refute QualityFilter.qualifies?(post)
    end

    test "returns false when post doesn't qualify" do
      post = %{
        author: qualifying_author(),
        text: "Short"
      }

      refute QualityFilter.qualifies?(post)
    end
  end

  describe "author_qualifies?/1" do
    test "returns true for qualifying author" do
      author = qualifying_author()
      assert QualityFilter.author_qualifies?(author)
    end

    test "requires minimum 500 followers" do
      author = %{qualifying_author() | followers_count: 499}
      refute QualityFilter.author_qualifies?(author)

      author = %{qualifying_author() | followers_count: 500}
      assert QualityFilter.author_qualifies?(author)
    end

    test "requires maximum 5000 following" do
      author = %{qualifying_author() | follows_count: 5001}
      refute QualityFilter.author_qualifies?(author)

      author = %{qualifying_author() | follows_count: 5000}
      assert QualityFilter.author_qualifies?(author)
    end

    test "requires non-empty bio" do
      author = %{qualifying_author() | description: nil}
      refute QualityFilter.author_qualifies?(author)

      author = %{qualifying_author() | description: ""}
      refute QualityFilter.author_qualifies?(author)

      author = %{qualifying_author() | description: "   "}
      refute QualityFilter.author_qualifies?(author)
    end

    test "requires account at least 365 days old" do
      recent_date = DateTime.add(DateTime.utc_now(), -364, :day)
      author = %{qualifying_author() | indexed_at: recent_date}
      refute QualityFilter.author_qualifies?(author)

      old_enough = DateTime.add(DateTime.utc_now(), -366, :day)
      author = %{qualifying_author() | indexed_at: old_enough}
      assert QualityFilter.author_qualifies?(author)
    end

    test "handles nil follower counts" do
      author = %{qualifying_author() | followers_count: nil}
      refute QualityFilter.author_qualifies?(author)
    end

    test "handles nil following counts" do
      author = %{qualifying_author() | follows_count: nil}
      assert QualityFilter.author_qualifies?(author)
    end
  end

  describe "post_qualifies?/1" do
    test "returns true for qualifying post content" do
      assert QualityFilter.post_qualifies?(long_text())
    end

    test "requires minimum 50 characters excluding hashtags" do
      # Just under 50 chars
      short = String.duplicate("a", 49)
      refute QualityFilter.post_qualifies?(short)

      # Exactly 50 chars
      exact = String.duplicate("a", 50)
      assert QualityFilter.post_qualifies?(exact)
    end

    test "excludes hashtags from text length" do
      # 40 chars of text + long hashtag = should fail
      text = "This is only forty characters of text. #verylonghashtag"
      refute QualityFilter.post_qualifies?(text)

      # 55 chars of text + hashtag = should pass
      text = "This is a much longer piece of text that passes easily! #tag"
      assert QualityFilter.post_qualifies?(text)
    end

    test "allows maximum 1 hashtag" do
      text = long_text() <> " #one"
      assert QualityFilter.post_qualifies?(text)

      text = long_text() <> " #one #two"
      refute QualityFilter.post_qualifies?(text)
    end

    test "allows maximum 1 emoji" do
      text = long_text() <> " 😀"
      assert QualityFilter.post_qualifies?(text)

      text = long_text() <> " 😀😎"
      refute QualityFilter.post_qualifies?(text)
    end

    test "returns false for nil text" do
      refute QualityFilter.post_qualifies?(nil)
    end

    test "returns false for non-string text" do
      refute QualityFilter.post_qualifies?(123)
    end
  end

  describe "domain_banned?/1" do
    test "returns true for banned URL shorteners" do
      assert QualityFilter.domain_banned?("https://bit.ly/abc123")
      assert QualityFilter.domain_banned?("https://tinyurl.com/xyz")
      assert QualityFilter.domain_banned?("https://t.co/short")
    end

    test "returns true for banned crypto exchanges" do
      assert QualityFilter.domain_banned?("https://coinbase.com/trade")
      assert QualityFilter.domain_banned?("https://binance.com/en")
      assert QualityFilter.domain_banned?("https://kraken.com")
    end

    test "returns true for banned NFT platforms" do
      assert QualityFilter.domain_banned?("https://opensea.io/collection/x")
      assert QualityFilter.domain_banned?("https://uniswap.org")
    end

    test "returns true for media hosts" do
      assert QualityFilter.domain_banned?("https://media.tenor.com/gif")
    end

    test "returns true for subdomains of banned domains" do
      assert QualityFilter.domain_banned?("https://app.uniswap.org/swap")
      assert QualityFilter.domain_banned?("https://pro.coinbase.com")
    end

    test "returns false for non-banned domains" do
      refute QualityFilter.domain_banned?("https://github.com/elixir")
      refute QualityFilter.domain_banned?("https://example.com")
      refute QualityFilter.domain_banned?("https://nytimes.com/article")
    end

    test "handles URLs without host" do
      refute QualityFilter.domain_banned?("/relative/path")
    end
  end

  describe "account_age_ok?/1" do
    test "returns true for old accounts" do
      old_date = DateTime.add(DateTime.utc_now(), -400, :day)
      assert QualityFilter.account_age_ok?(old_date)
    end

    test "returns false for new accounts" do
      new_date = DateTime.add(DateTime.utc_now(), -30, :day)
      refute QualityFilter.account_age_ok?(new_date)
    end

    test "returns false for nil" do
      refute QualityFilter.account_age_ok?(nil)
    end

    test "boundary at 365 days" do
      exactly_365 = DateTime.add(DateTime.utc_now(), -365, :day)
      assert QualityFilter.account_age_ok?(exactly_365)

      just_under = DateTime.add(DateTime.utc_now(), -364, :day)
      refute QualityFilter.account_age_ok?(just_under)
    end
  end

  describe "count_hashtags/1" do
    test "counts hashtags in text" do
      assert QualityFilter.count_hashtags("Hello #world") == 1
      assert QualityFilter.count_hashtags("#one #two #three") == 3
      assert QualityFilter.count_hashtags("No hashtags here") == 0
    end

    test "handles empty string" do
      assert QualityFilter.count_hashtags("") == 0
    end

    test "counts hashtags with numbers" do
      assert QualityFilter.count_hashtags("#tag123 #456tag") == 2
    end
  end

  describe "count_emojis/1" do
    test "counts common emojis" do
      assert QualityFilter.count_emojis("Hello 👋 World 🌍") == 2
      assert QualityFilter.count_emojis("😀😎🎉") == 3
      assert QualityFilter.count_emojis("No emojis") == 0
    end

    test "handles empty string" do
      assert QualityFilter.count_emojis("") == 0
    end

    test "counts various emoji categories" do
      # Miscellaneous symbols
      assert QualityFilter.count_emojis("☀️") >= 1
      # Dingbats
      assert QualityFilter.count_emojis("✨") >= 1
      # Emoticons
      assert QualityFilter.count_emojis("😀") == 1
      # Transport
      assert QualityFilter.count_emojis("🚀") == 1
    end
  end

  describe "calculate_score/1" do
    test "returns 0 for nil author" do
      assert QualityFilter.calculate_score(%{author: nil}) == 0
    end

    test "increases with follower count (log scale)" do
      score_100 = QualityFilter.calculate_score(%{author: %{followers_count: 100, follows_count: 100}})
      score_1000 = QualityFilter.calculate_score(%{author: %{followers_count: 1000, follows_count: 100}})
      score_10000 = QualityFilter.calculate_score(%{author: %{followers_count: 10000, follows_count: 100}})

      assert score_1000 > score_100
      assert score_10000 > score_1000
      # Log scale means diminishing returns
      assert (score_10000 - score_1000) < (score_1000 - score_100) * 2
    end

    test "rewards good follower/following ratio" do
      # Same followers, different following
      high_ratio = QualityFilter.calculate_score(%{author: %{followers_count: 1000, follows_count: 100}})
      low_ratio = QualityFilter.calculate_score(%{author: %{followers_count: 1000, follows_count: 900}})

      assert high_ratio > low_ratio
    end

    test "caps at 100" do
      huge = QualityFilter.calculate_score(%{author: %{followers_count: 10_000_000, follows_count: 1}})
      assert huge == 100
    end

    test "handles nil follower counts" do
      score = QualityFilter.calculate_score(%{author: %{followers_count: nil, follows_count: 100}})
      assert is_integer(score)
    end

    test "handles nil following counts" do
      score = QualityFilter.calculate_score(%{author: %{followers_count: 1000, follows_count: nil}})
      assert is_integer(score)
    end
  end

  describe "banned_domains/0" do
    test "returns list of banned domains" do
      domains = QualityFilter.banned_domains()
      assert is_list(domains)
      assert "bit.ly" in domains
      assert "coinbase.com" in domains
    end
  end

  describe "thresholds/0" do
    test "returns map of thresholds" do
      thresholds = QualityFilter.thresholds()

      assert thresholds.min_followers == 500
      assert thresholds.max_following == 5000
      assert thresholds.min_account_age_days == 365
      assert thresholds.min_text_length == 50
      assert thresholds.max_hashtags == 1
      assert thresholds.max_emojis == 1
    end
  end

  # Test fixtures

  defp qualifying_author do
    %{
      followers_count: 1000,
      follows_count: 200,
      description: "A developer who loves Elixir",
      indexed_at: old_date()
    }
  end

  defp qualifying_post do
    %{
      author: qualifying_author(),
      text: long_text()
    }
  end

  defp long_text do
    "This is a sufficiently long piece of text that definitely exceeds fifty characters"
  end

  defp old_date do
    DateTime.add(DateTime.utc_now(), -400, :day)
  end
end
