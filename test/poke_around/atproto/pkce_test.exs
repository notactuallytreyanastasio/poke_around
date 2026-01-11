defmodule PokeAround.ATProto.PKCETest do
  use ExUnit.Case, async: true

  alias PokeAround.ATProto.PKCE

  describe "generate_verifier/0" do
    test "returns a string" do
      verifier = PKCE.generate_verifier()
      assert is_binary(verifier)
    end

    test "returns URL-safe base64" do
      verifier = PKCE.generate_verifier()
      # URL-safe base64 only contains these characters
      assert Regex.match?(~r/^[A-Za-z0-9_-]+$/, verifier)
    end

    test "returns different values on each call" do
      v1 = PKCE.generate_verifier()
      v2 = PKCE.generate_verifier()
      refute v1 == v2
    end

    test "returns appropriate length (43+ chars for 32 bytes)" do
      verifier = PKCE.generate_verifier()
      # 32 bytes base64-encoded = 43 characters (without padding)
      assert String.length(verifier) >= 43
    end
  end

  describe "generate_challenge/1" do
    test "returns a string" do
      verifier = PKCE.generate_verifier()
      challenge = PKCE.generate_challenge(verifier)
      assert is_binary(challenge)
    end

    test "returns URL-safe base64" do
      challenge = PKCE.generate_challenge("test-verifier")
      assert Regex.match?(~r/^[A-Za-z0-9_-]+$/, challenge)
    end

    test "produces consistent output for same input" do
      verifier = "consistent-test-verifier"
      c1 = PKCE.generate_challenge(verifier)
      c2 = PKCE.generate_challenge(verifier)
      assert c1 == c2
    end

    test "produces different output for different input" do
      c1 = PKCE.generate_challenge("verifier-a")
      c2 = PKCE.generate_challenge("verifier-b")
      refute c1 == c2
    end

    test "returns 43-char hash (SHA256 = 32 bytes = 43 base64 chars)" do
      challenge = PKCE.generate_challenge("any-verifier")
      assert String.length(challenge) == 43
    end
  end

  describe "generate/0" do
    test "returns tuple of {verifier, challenge}" do
      {verifier, challenge} = PKCE.generate()
      assert is_binary(verifier)
      assert is_binary(challenge)
    end

    test "verifier and challenge are different" do
      {verifier, challenge} = PKCE.generate()
      refute verifier == challenge
    end

    test "challenge is derived from verifier" do
      {verifier, challenge} = PKCE.generate()
      assert PKCE.generate_challenge(verifier) == challenge
    end
  end

  describe "verify/2" do
    test "returns true for matching verifier and challenge" do
      {verifier, challenge} = PKCE.generate()
      assert PKCE.verify(verifier, challenge) == true
    end

    test "returns false for non-matching verifier" do
      {_verifier, challenge} = PKCE.generate()
      assert PKCE.verify("wrong-verifier", challenge) == false
    end

    test "returns false for non-matching challenge" do
      {verifier, _challenge} = PKCE.generate()
      assert PKCE.verify(verifier, "wrong-challenge") == false
    end

    test "verifies manually created pairs" do
      verifier = "my-custom-verifier-string"
      challenge = PKCE.generate_challenge(verifier)
      assert PKCE.verify(verifier, challenge) == true
    end
  end
end
