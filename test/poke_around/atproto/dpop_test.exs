defmodule PokeAround.ATProto.DPoPTest do
  use ExUnit.Case, async: true

  alias PokeAround.ATProto.DPoP

  describe "generate_keypair/0" do
    test "returns {private_key, public_jwk} tuple" do
      {private_key, public_jwk} = DPoP.generate_keypair()
      assert private_key != nil
      assert is_map(public_jwk)
    end

    test "public_jwk has required EC fields" do
      {_private_key, public_jwk} = DPoP.generate_keypair()

      assert public_jwk["kty"] == "EC"
      assert public_jwk["crv"] == "P-256"
      assert is_binary(public_jwk["x"])
      assert is_binary(public_jwk["y"])
    end

    test "generates unique keypairs" do
      {_pk1, jwk1} = DPoP.generate_keypair()
      {_pk2, jwk2} = DPoP.generate_keypair()

      refute jwk1["x"] == jwk2["x"]
      refute jwk1["y"] == jwk2["y"]
    end
  end

  describe "create_proof/5" do
    setup do
      {private_key, public_jwk} = DPoP.generate_keypair()
      {:ok, private_key: private_key, public_jwk: public_jwk}
    end

    test "returns a JWT string", %{private_key: pk, public_jwk: jwk} do
      proof = DPoP.create_proof(pk, jwk, "POST", "https://auth.example.com/token")
      assert is_binary(proof)
      # JWTs have 3 parts separated by dots
      assert length(String.split(proof, ".")) == 3
    end

    test "JWT header has correct typ and alg", %{private_key: pk, public_jwk: jwk} do
      proof = DPoP.create_proof(pk, jwk, "POST", "https://auth.example.com/token")

      [header_b64, _, _] = String.split(proof, ".")
      header = header_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!()

      assert header["typ"] == "dpop+jwt"
      assert header["alg"] == "ES256"
    end

    test "JWT header includes public key", %{private_key: pk, public_jwk: jwk} do
      proof = DPoP.create_proof(pk, jwk, "POST", "https://auth.example.com/token")

      [header_b64, _, _] = String.split(proof, ".")
      header = header_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!()

      assert header["jwk"]["kty"] == "EC"
      assert header["jwk"]["crv"] == "P-256"
    end

    test "JWT payload has required claims", %{private_key: pk, public_jwk: jwk} do
      proof = DPoP.create_proof(pk, jwk, "POST", "https://auth.example.com/token")

      [_, payload_b64, _] = String.split(proof, ".")
      payload = payload_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!()

      assert is_binary(payload["jti"])
      assert payload["htm"] == "POST"
      assert payload["htu"] == "https://auth.example.com/token"
      assert is_integer(payload["iat"])
      assert is_integer(payload["exp"])
      assert payload["exp"] > payload["iat"]
    end

    test "uppercases HTTP method", %{private_key: pk, public_jwk: jwk} do
      proof = DPoP.create_proof(pk, jwk, "post", "https://auth.example.com/token")

      [_, payload_b64, _] = String.split(proof, ".")
      payload = payload_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!()

      assert payload["htm"] == "POST"
    end

    test "includes nonce when provided", %{private_key: pk, public_jwk: jwk} do
      proof = DPoP.create_proof(pk, jwk, "POST", "https://auth.example.com/token", "server-nonce-123")

      [_, payload_b64, _] = String.split(proof, ".")
      payload = payload_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!()

      assert payload["nonce"] == "server-nonce-123"
    end

    test "omits nonce when nil", %{private_key: pk, public_jwk: jwk} do
      proof = DPoP.create_proof(pk, jwk, "POST", "https://auth.example.com/token", nil)

      [_, payload_b64, _] = String.split(proof, ".")
      payload = payload_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!()

      refute Map.has_key?(payload, "nonce")
    end

    test "strips query params from htu", %{private_key: pk, public_jwk: jwk} do
      proof = DPoP.create_proof(pk, jwk, "GET", "https://api.example.com/resource?param=value")

      [_, payload_b64, _] = String.split(proof, ".")
      payload = payload_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!()

      assert payload["htu"] == "https://api.example.com/resource"
    end
  end

  describe "create_proof_with_ath/6" do
    setup do
      {private_key, public_jwk} = DPoP.generate_keypair()
      {:ok, private_key: private_key, public_jwk: public_jwk}
    end

    test "includes access token hash (ath)", %{private_key: pk, public_jwk: jwk} do
      access_token = "my-access-token-123"
      proof = DPoP.create_proof_with_ath(pk, jwk, "GET", "https://api.example.com/resource", access_token)

      [_, payload_b64, _] = String.split(proof, ".")
      payload = payload_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!()

      assert is_binary(payload["ath"])
      # ath is SHA256 hash of token, base64url encoded (43 chars)
      assert String.length(payload["ath"]) == 43
    end

    test "different tokens produce different ath", %{private_key: pk, public_jwk: jwk} do
      proof1 = DPoP.create_proof_with_ath(pk, jwk, "GET", "https://api.example.com", "token-1")
      proof2 = DPoP.create_proof_with_ath(pk, jwk, "GET", "https://api.example.com", "token-2")

      [_, p1_b64, _] = String.split(proof1, ".")
      [_, p2_b64, _] = String.split(proof2, ".")
      p1 = p1_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!()
      p2 = p2_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!()

      refute p1["ath"] == p2["ath"]
    end

    test "includes nonce with ath when provided", %{private_key: pk, public_jwk: jwk} do
      proof = DPoP.create_proof_with_ath(pk, jwk, "GET", "https://api.example.com", "token", "nonce-123")

      [_, payload_b64, _] = String.split(proof, ".")
      payload = payload_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!()

      assert payload["nonce"] == "nonce-123"
      assert is_binary(payload["ath"])
    end
  end

  describe "serialize_keypair/1 and deserialize_keypair/1" do
    test "roundtrip preserves keypair functionality" do
      original = DPoP.generate_keypair()
      serialized = DPoP.serialize_keypair(original)
      restored = DPoP.deserialize_keypair(serialized)

      {pk_orig, jwk_orig} = original
      {pk_rest, jwk_rest} = restored

      # Create proofs with both and verify they're structurally valid
      proof_orig = DPoP.create_proof(pk_orig, jwk_orig, "POST", "https://example.com")
      proof_rest = DPoP.create_proof(pk_rest, jwk_rest, "POST", "https://example.com")

      # Both should be valid JWTs
      assert length(String.split(proof_orig, ".")) == 3
      assert length(String.split(proof_rest, ".")) == 3
    end

    test "serialized format has expected structure" do
      keypair = DPoP.generate_keypair()
      serialized = DPoP.serialize_keypair(keypair)

      assert is_map(serialized)
      assert is_map(serialized["private"])
      assert is_map(serialized["public"])
      assert serialized["public"]["kty"] == "EC"
    end

    test "serialized format is JSON-encodable" do
      keypair = DPoP.generate_keypair()
      serialized = DPoP.serialize_keypair(keypair)

      assert {:ok, json} = Jason.encode(serialized)
      assert is_binary(json)

      # Can decode back
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["public"]["kty"] == "EC"
    end
  end
end
