defmodule PokeAround.ATProto.DPoP do
  @moduledoc """
  DPoP (Demonstrating Proof of Possession) implementation for ATProto OAuth.

  DPoP is mandatory for all ATProto OAuth clients. Each authentication session
  requires a unique ES256 keypair that proves possession of the token.
  """

  @doc """
  Generate a new ES256 keypair for DPoP.

  Returns `{private_key, public_jwk}` where:
  - `private_key` is the JOSE key for signing
  - `public_jwk` is the public key as a JWK map for the DPoP header
  """
  def generate_keypair do
    # Generate EC key on P-256 curve (ES256)
    {_type, private_key} = JOSE.JWK.generate_key({:ec, :secp256r1}) |> JOSE.JWK.to_key()

    # Create JOSE JWK from the private key
    jwk = JOSE.JWK.from_key(private_key)

    # Extract public JWK for the header
    {_kty, public_jwk_map} = JOSE.JWK.to_public(jwk) |> JOSE.JWK.to_map()

    {jwk, public_jwk_map}
  end

  @doc """
  Create a DPoP proof JWT for the token endpoint.

  ## Parameters

  - `private_key` - JOSE JWK private key
  - `public_jwk` - Public key as JWK map
  - `http_method` - HTTP method (e.g., "POST")
  - `url` - Target URL
  - `nonce` - Server-provided nonce (nil for first request)

  ## Returns

  DPoP JWT string
  """
  def create_proof(private_key, public_jwk, http_method, url, nonce \\ nil) do
    jti = generate_jti()
    now = System.os_time(:second)

    # DPoP JWT header
    header = %{
      "typ" => "dpop+jwt",
      "alg" => "ES256",
      "jwk" => public_jwk
    }

    # DPoP JWT payload
    payload =
      %{
        "jti" => jti,
        "htm" => String.upcase(to_string(http_method)),
        "htu" => normalize_url(url),
        "iat" => now,
        "exp" => now + 300
      }
      |> maybe_add_nonce(nonce)

    {_alg, jwt} = JOSE.JWT.sign(private_key, header, payload) |> JOSE.JWS.compact()
    jwt
  end

  @doc """
  Create a DPoP proof JWT for resource server requests (includes access token hash).

  ## Parameters

  - `private_key` - JOSE JWK private key
  - `public_jwk` - Public key as JWK map
  - `http_method` - HTTP method
  - `url` - Target URL
  - `access_token` - The access token to bind
  - `nonce` - Server-provided nonce
  """
  def create_proof_with_ath(private_key, public_jwk, http_method, url, access_token, nonce \\ nil) do
    jti = generate_jti()
    now = System.os_time(:second)

    # Calculate access token hash (ath)
    ath = hash_token(access_token)

    header = %{
      "typ" => "dpop+jwt",
      "alg" => "ES256",
      "jwk" => public_jwk
    }

    payload =
      %{
        "jti" => jti,
        "htm" => String.upcase(to_string(http_method)),
        "htu" => normalize_url(url),
        "iat" => now,
        "exp" => now + 300,
        "ath" => ath
      }
      |> maybe_add_nonce(nonce)

    {_alg, jwt} = JOSE.JWT.sign(private_key, header, payload) |> JOSE.JWS.compact()
    jwt
  end

  @doc """
  Serialize a keypair to a storable format.
  """
  def serialize_keypair({private_key, public_jwk}) do
    {_kty, private_map} = JOSE.JWK.to_map(private_key)

    %{
      "private" => private_map,
      "public" => public_jwk
    }
  end

  @doc """
  Deserialize a keypair from stored format.
  """
  def deserialize_keypair(%{"private" => private_map, "public" => public_jwk}) do
    private_key = JOSE.JWK.from_map(private_map)
    {private_key, public_jwk}
  end

  # Private functions

  defp generate_jti do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp hash_token(token) do
    :crypto.hash(:sha256, token) |> Base.url_encode64(padding: false)
  end

  defp normalize_url(url) do
    # Remove query string and fragment for htu
    uri = URI.parse(url)
    URI.to_string(%{uri | query: nil, fragment: nil})
  end

  defp maybe_add_nonce(payload, nil), do: payload
  defp maybe_add_nonce(payload, nonce), do: Map.put(payload, "nonce", nonce)
end
