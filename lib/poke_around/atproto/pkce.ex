defmodule PokeAround.ATProto.PKCE do
  @moduledoc """
  PKCE (Proof Key for Code Exchange) implementation for ATProto OAuth.

  PKCE is mandatory for all ATProto OAuth clients and must use S256 method.
  """

  @doc """
  Generate a PKCE code verifier.

  Returns a random 43-128 character URL-safe string.
  The ATProto spec recommends 32-96 random bytes, base64url encoded.
  """
  def generate_verifier do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Generate a code challenge from a verifier using S256 method.

  S256 = BASE64URL(SHA256(code_verifier))
  """
  def generate_challenge(verifier) do
    :crypto.hash(:sha256, verifier)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Generate a verifier and challenge pair.

  Returns `{verifier, challenge}`.
  """
  def generate do
    verifier = generate_verifier()
    challenge = generate_challenge(verifier)
    {verifier, challenge}
  end

  @doc """
  Verify that a verifier matches a challenge.
  """
  def verify(verifier, challenge) do
    generate_challenge(verifier) == challenge
  end
end
