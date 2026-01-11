defmodule PokeAround.Links.QualityFilter do
  @moduledoc """
  Pure functions for filtering link quality.

  Extracted from Extractor for testability. All functions are pure -
  they take data and return data with no side effects.

  ## Quality Criteria

  Posts must meet all of these criteria to qualify:

  - **Author requirements**:
    - Minimum 500 followers
    - Maximum 5000 following (filters out bots)
    - Has a bio (description)
    - Account at least 365 days old

  - **Post content requirements**:
    - At least 50 characters of text (excluding hashtags)
    - Maximum 1 hashtag
    - Maximum 1 emoji

  - **Link requirements**:
    - Single link per post (multiple = spam)
    - Domain not banned (URL shorteners, crypto, etc.)

  ## Examples

      iex> author = %{followers_count: 1000, follows_count: 500, description: "Hi", indexed_at: ~U[2020-01-01 00:00:00Z]}
      iex> QualityFilter.author_qualifies?(author)
      true

      iex> QualityFilter.domain_banned?("https://bit.ly/abc123")
      true

      iex> QualityFilter.post_qualifies?("Check out this amazing article about Elixir programming!")
      true

  """

  alias PokeAround.Bluesky.Types.{Author, Post}

  # Quality thresholds
  @min_followers 500
  @max_following 5000
  @min_account_age_days 365
  @min_text_length 50
  @max_hashtags 1
  @max_emojis 1

  # Banned domains (URL shorteners, spam magnets, media hosts, crypto)
  @banned_domains [
    # URL shorteners
    "tinyurl.com",
    "bit.ly",
    "t.co",
    # Media hosts
    "media.tenor.com",
    # Crypto exchanges
    "coinbase.com",
    "binance.com",
    "binance.us",
    "kraken.com",
    "crypto.com",
    "gemini.com",
    "kucoin.com",
    "bybit.com",
    "okx.com",
    "bitfinex.com",
    "bitstamp.net",
    "gate.io",
    "huobi.com",
    "mexc.com",
    "bitget.com",
    # Crypto news/media
    "coindesk.com",
    "cointelegraph.com",
    "decrypt.co",
    "theblock.co",
    "bitcoinmagazine.com",
    # NFT/DeFi
    "opensea.io",
    "uniswap.org",
    "rarible.com",
    "foundation.app",
    "blur.io",
    "looksrare.org",
    "pancakeswap.finance",
    "aave.com",
    # Crypto trackers
    "coingecko.com",
    "coinmarketcap.com",
    "dextools.io",
    "dexscreener.com",
    # Meme coin pumps
    "pump.fun",
    # Wallets
    "metamask.io",
    "phantom.app",
    "trustwallet.com"
  ]

  @doc """
  Check if a post qualifies for link extraction.

  A post qualifies if:
  - It has an author
  - The author meets quality criteria
  - The post content meets quality criteria

  ## Examples

      iex> post = %{author: nil, text: "Hello"}
      iex> QualityFilter.qualifies?(post)
      false

  """
  @spec qualifies?(Post.t() | map()) :: boolean()
  def qualifies?(%{author: nil}), do: false

  def qualifies?(%{author: author, text: text}) do
    author_qualifies?(author) && post_qualifies?(text)
  end

  @doc """
  Check if an author meets quality criteria.

  Criteria:
  - At least #{@min_followers} followers
  - At most #{@max_following} following
  - Has a non-empty bio/description
  - Account at least #{@min_account_age_days} days old

  ## Examples

      iex> author = %{followers_count: 1000, follows_count: 100, description: "Developer", indexed_at: ~U[2020-01-01 00:00:00Z]}
      iex> QualityFilter.author_qualifies?(author)
      true

      iex> author = %{followers_count: 100, follows_count: 100, description: "Hi", indexed_at: ~U[2020-01-01 00:00:00Z]}
      iex> QualityFilter.author_qualifies?(author)
      false

  """
  @spec author_qualifies?(Author.t() | map()) :: boolean()
  def author_qualifies?(author) do
    followers = author.followers_count || 0
    following = author.follows_count || 0
    has_bio = author.description != nil && String.trim(author.description) != ""
    account_old_enough = account_age_ok?(author.indexed_at)

    followers >= @min_followers &&
      following <= @max_following &&
      has_bio &&
      account_old_enough
  end

  @doc """
  Check if post content meets quality criteria.

  Criteria:
  - At least #{@min_text_length} characters (excluding hashtags)
  - At most #{@max_hashtags} hashtag(s)
  - At most #{@max_emojis} emoji(s)

  ## Examples

      iex> QualityFilter.post_qualifies?("This is a great article about functional programming in Elixir!")
      true

      iex> QualityFilter.post_qualifies?("Short")
      false

      iex> QualityFilter.post_qualifies?("Good content #tag1 #tag2 #tag3")
      false

  """
  @spec post_qualifies?(String.t() | nil) :: boolean()
  def post_qualifies?(text) when is_binary(text) do
    hashtag_count = count_hashtags(text)
    emoji_count = count_emojis(text)

    # Text length AFTER removing hashtags - must have real content
    text_without_hashtags = Regex.replace(~r/#\w+/, text, "") |> String.trim()
    clean_text_length = String.length(text_without_hashtags)

    clean_text_length >= @min_text_length &&
      hashtag_count <= @max_hashtags &&
      emoji_count <= @max_emojis
  end

  def post_qualifies?(_), do: false

  @doc """
  Check if a URL's domain is banned.

  Banned domains include:
  - URL shorteners (bit.ly, t.co, tinyurl.com)
  - Crypto exchanges (coinbase, binance, etc.)
  - NFT/DeFi platforms (opensea, uniswap, etc.)
  - Media hosts (tenor)

  Also matches subdomains (e.g., "app.uniswap.org" is banned).

  ## Examples

      iex> QualityFilter.domain_banned?("https://bit.ly/abc123")
      true

      iex> QualityFilter.domain_banned?("https://app.uniswap.org/swap")
      true

      iex> QualityFilter.domain_banned?("https://github.com/elixir-lang/elixir")
      false

  """
  @spec domain_banned?(String.t()) :: boolean()
  def domain_banned?(url) do
    uri = URI.parse(url)
    host = uri.host || ""

    Enum.any?(@banned_domains, fn banned ->
      host == banned || String.ends_with?(host, "." <> banned)
    end)
  end

  @doc """
  Check if an account is old enough.

  Returns true if the account was created at least #{@min_account_age_days} days ago.

  ## Examples

      iex> QualityFilter.account_age_ok?(~U[2020-01-01 00:00:00Z])
      true

      iex> QualityFilter.account_age_ok?(nil)
      false

  """
  @spec account_age_ok?(DateTime.t() | nil) :: boolean()
  def account_age_ok?(nil), do: false

  def account_age_ok?(%DateTime{} = indexed_at) do
    days_old = DateTime.diff(DateTime.utc_now(), indexed_at, :day)
    days_old >= @min_account_age_days
  end

  @doc """
  Count hashtags in text.

  ## Examples

      iex> QualityFilter.count_hashtags("Hello #world #elixir")
      2

      iex> QualityFilter.count_hashtags("No hashtags here")
      0

  """
  @spec count_hashtags(String.t()) :: non_neg_integer()
  def count_hashtags(text) do
    ~r/#\w+/
    |> Regex.scan(text)
    |> length()
  end

  @doc """
  Count emojis in text.

  ## Examples

      iex> QualityFilter.count_emojis("Hello 👋 World 🌍")
      2

      iex> QualityFilter.count_emojis("No emojis")
      0

  """
  @spec count_emojis(String.t()) :: non_neg_integer()
  def count_emojis(text) do
    # Match common emoji ranges
    ~r/[\x{1F300}-\x{1F9FF}]|[\x{2600}-\x{26FF}]|[\x{2700}-\x{27BF}]|[\x{1F600}-\x{1F64F}]|[\x{1F680}-\x{1F6FF}]/u
    |> Regex.scan(text)
    |> length()
  end

  @doc """
  Calculate a quality score for a post based on author metrics.

  Score is based on:
  - Follower count (log scale, diminishing returns)
  - Follower/following ratio (curated taste bonus)

  Returns a score from 0-100.

  ## Examples

      iex> author = %{followers_count: 10000, follows_count: 100}
      iex> score = QualityFilter.calculate_score(%{author: author})
      iex> score > 50
      true

  """
  @spec calculate_score(Post.t() | map()) :: non_neg_integer()
  def calculate_score(%{author: nil}), do: 0

  def calculate_score(%{author: author}) do
    followers = author.followers_count || 0
    following = author.follows_count || 1

    # Base score from followers (log scale, diminishing returns)
    follower_score = :math.log10(max(followers, 1)) * 15

    # Bonus for good follower/following ratio (curated taste, not follow-for-follow)
    ratio = followers / max(following, 1)
    ratio_bonus = min(ratio * 5, 20)

    # Combined score, capped at 100
    min(round(follower_score + ratio_bonus), 100)
  end

  @doc """
  Get the list of banned domains.

  Useful for debugging and testing.
  """
  @spec banned_domains() :: [String.t()]
  def banned_domains, do: @banned_domains

  @doc """
  Get quality thresholds.

  Returns a map of all configurable thresholds.
  """
  @spec thresholds() :: map()
  def thresholds do
    %{
      min_followers: @min_followers,
      max_following: @max_following,
      min_account_age_days: @min_account_age_days,
      min_text_length: @min_text_length,
      max_hashtags: @max_hashtags,
      max_emojis: @max_emojis
    }
  end
end
