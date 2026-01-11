defmodule PokeAround.Links.LinkTest do
  use PokeAround.DataCase, async: true

  alias PokeAround.Links.Link

  describe "hash_url/1" do
    test "produces consistent hash for same URL" do
      url = "https://example.com/page"
      assert Link.hash_url(url) == Link.hash_url(url)
    end

    test "normalizes case in host" do
      assert Link.hash_url("https://EXAMPLE.COM/page") ==
               Link.hash_url("https://example.com/page")
    end

    test "normalizes trailing slashes" do
      assert Link.hash_url("https://example.com/") ==
               Link.hash_url("https://example.com")
    end

    test "sorts query parameters" do
      assert Link.hash_url("https://example.com?b=2&a=1") ==
               Link.hash_url("https://example.com?a=1&b=2")
    end

    test "different URLs produce different hashes" do
      refute Link.hash_url("https://example.com/a") ==
               Link.hash_url("https://example.com/b")
    end

    test "handles URLs without host gracefully" do
      # Should not crash, returns some hash
      hash = Link.hash_url("/relative/path")
      assert is_binary(hash)
      assert String.length(hash) == 32
    end

    test "returns 32-character hash" do
      hash = Link.hash_url("https://example.com")
      assert String.length(hash) == 32
      assert Regex.match?(~r/^[a-f0-9]+$/, hash)
    end
  end

  describe "extract_domain/1" do
    test "extracts domain from HTTPS URL" do
      assert Link.extract_domain("https://example.com/path") == "example.com"
    end

    test "extracts domain from HTTP URL" do
      assert Link.extract_domain("http://example.com/path") == "example.com"
    end

    test "removes www prefix" do
      assert Link.extract_domain("https://www.example.com") == "example.com"
    end

    test "lowercases domain" do
      assert Link.extract_domain("https://EXAMPLE.COM") == "example.com"
    end

    test "handles subdomains" do
      assert Link.extract_domain("https://sub.example.com") == "sub.example.com"
    end

    test "handles www subdomain with other subdomains" do
      assert Link.extract_domain("https://www.sub.example.com") == "sub.example.com"
    end

    test "returns nil for invalid URLs" do
      assert Link.extract_domain("not a url") == nil
    end

    test "returns nil for relative paths" do
      assert Link.extract_domain("/relative/path") == nil
    end
  end

  describe "changeset/2" do
    test "valid with required fields" do
      attrs = %{url: "https://example.com", url_hash: "abc123"}
      changeset = Link.changeset(%Link{}, attrs)
      assert changeset.valid?
    end

    test "invalid without url" do
      attrs = %{url_hash: "abc123"}
      changeset = Link.changeset(%Link{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).url
    end

    test "invalid without url_hash" do
      attrs = %{url: "https://example.com"}
      changeset = Link.changeset(%Link{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).url_hash
    end

    test "accepts optional fields" do
      attrs = %{
        url: "https://example.com",
        url_hash: "abc123",
        post_text: "Check out this link",
        author_handle: "user.bsky.social",
        score: 85,
        domain: "example.com",
        tags: ["tech", "news"],
        langs: ["en"]
      }

      changeset = Link.changeset(%Link{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :post_text) == "Check out this link"
      assert Ecto.Changeset.get_change(changeset, :score) == 85
    end

    test "enforces unique url_hash constraint" do
      attrs = %{url: "https://example.com", url_hash: "unique123"}

      {:ok, _link} =
        %Link{}
        |> Link.changeset(attrs)
        |> Repo.insert()

      {:error, changeset} =
        %Link{}
        |> Link.changeset(attrs)
        |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).url_hash
    end
  end
end
