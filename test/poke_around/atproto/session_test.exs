defmodule PokeAround.ATProto.SessionTest do
  use PokeAround.DataCase, async: true

  alias PokeAround.ATProto.{Session, DPoP, OAuth}
  alias PokeAround.Repo

  describe "changeset/2" do
    test "valid with required fields" do
      {_pk, _jwk} = keypair = DPoP.generate_keypair()
      serialized = keypair |> DPoP.serialize_keypair() |> Jason.encode!()

      attrs = %{
        user_did: "did:plc:abc123",
        dpop_keypair: serialized,
        pds_url: "https://pds.example.com"
      }

      changeset = Session.changeset(%Session{}, attrs)
      assert changeset.valid?
    end

    test "invalid without user_did" do
      {_pk, _jwk} = keypair = DPoP.generate_keypair()
      serialized = keypair |> DPoP.serialize_keypair() |> Jason.encode!()

      attrs = %{
        dpop_keypair: serialized,
        pds_url: "https://pds.example.com"
      }

      changeset = Session.changeset(%Session{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).user_did
    end

    test "invalid without dpop_keypair" do
      attrs = %{
        user_did: "did:plc:abc123",
        pds_url: "https://pds.example.com"
      }

      changeset = Session.changeset(%Session{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).dpop_keypair
    end

    test "invalid without pds_url" do
      {_pk, _jwk} = keypair = DPoP.generate_keypair()
      serialized = keypair |> DPoP.serialize_keypair() |> Jason.encode!()

      attrs = %{
        user_did: "did:plc:abc123",
        dpop_keypair: serialized
      }

      changeset = Session.changeset(%Session{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).pds_url
    end

    test "accepts optional fields" do
      keypair = DPoP.generate_keypair()
      serialized = keypair |> DPoP.serialize_keypair() |> Jason.encode!()
      expires = DateTime.utc_now() |> DateTime.add(1, :hour)

      attrs = %{
        user_did: "did:plc:abc123",
        dpop_keypair: serialized,
        pds_url: "https://pds.example.com",
        handle: "user.bsky.social",
        access_token: "access123",
        refresh_token: "refresh456",
        auth_server_url: "https://auth.example.com",
        scope: "atproto transition:generic",
        expires_at: expires
      }

      changeset = Session.changeset(%Session{}, attrs)
      assert changeset.valid?
    end

    test "enforces unique user_did constraint" do
      keypair = DPoP.generate_keypair()
      serialized = keypair |> DPoP.serialize_keypair() |> Jason.encode!()

      attrs = %{
        user_did: "did:plc:unique-test",
        dpop_keypair: serialized,
        pds_url: "https://pds.example.com"
      }

      {:ok, _} = %Session{} |> Session.changeset(attrs) |> Repo.insert()

      {:error, changeset} = %Session{} |> Session.changeset(attrs) |> Repo.insert()
      assert "has already been taken" in errors_on(changeset).user_did
    end
  end

  describe "from_oauth_session/1" do
    test "converts OAuth.Session to persistable map" do
      keypair = DPoP.generate_keypair()
      expires = DateTime.utc_now() |> DateTime.add(1, :hour)

      oauth_session = %OAuth.Session{
        did: "did:plc:test123",
        handle: "test.bsky.social",
        access_token: "access_xyz",
        refresh_token: "refresh_xyz",
        dpop_keypair: keypair,
        pds_url: "https://pds.bsky.network",
        auth_server_url: "https://bsky.social",
        scope: "atproto transition:generic",
        expires_at: expires,
        auth_server_nonce: "auth-nonce",
        resource_server_nonce: "resource-nonce"
      }

      map = Session.from_oauth_session(oauth_session)

      assert map.user_did == "did:plc:test123"
      assert map.handle == "test.bsky.social"
      assert map.access_token == "access_xyz"
      assert map.refresh_token == "refresh_xyz"
      assert map.pds_url == "https://pds.bsky.network"
      assert map.auth_server_url == "https://bsky.social"
      assert map.scope == "atproto transition:generic"
      assert map.expires_at == expires
      assert map.auth_server_nonce == "auth-nonce"
      assert map.resource_server_nonce == "resource-nonce"

      # dpop_keypair should be JSON-encoded
      assert is_binary(map.dpop_keypair)
      assert {:ok, decoded} = Jason.decode(map.dpop_keypair)
      assert is_map(decoded["private"])
      assert is_map(decoded["public"])
    end
  end

  describe "to_oauth_session/1" do
    test "converts Ecto session to OAuth.Session" do
      keypair = DPoP.generate_keypair()
      serialized = keypair |> DPoP.serialize_keypair() |> Jason.encode!()
      expires = DateTime.utc_now() |> DateTime.add(1, :hour) |> DateTime.truncate(:microsecond)

      ecto_session = %Session{
        user_did: "did:plc:convert",
        handle: "convert.bsky.social",
        access_token: "access_abc",
        refresh_token: "refresh_abc",
        dpop_keypair: serialized,
        pds_url: "https://pds.example.com",
        auth_server_url: "https://auth.example.com",
        scope: "atproto",
        expires_at: expires,
        auth_server_nonce: "a-nonce",
        resource_server_nonce: "r-nonce"
      }

      oauth = Session.to_oauth_session(ecto_session)

      assert %OAuth.Session{} = oauth
      assert oauth.did == "did:plc:convert"
      assert oauth.handle == "convert.bsky.social"
      assert oauth.access_token == "access_abc"
      assert oauth.refresh_token == "refresh_abc"
      assert oauth.pds_url == "https://pds.example.com"
      assert oauth.auth_server_url == "https://auth.example.com"
      assert oauth.scope == "atproto"
      assert oauth.expires_at == expires
      assert oauth.auth_server_nonce == "a-nonce"
      assert oauth.resource_server_nonce == "r-nonce"

      # dpop_keypair should be deserialized
      {pk, jwk} = oauth.dpop_keypair
      assert pk != nil
      assert is_map(jwk)
    end
  end

  describe "roundtrip conversion" do
    test "from_oauth_session -> insert -> fetch -> to_oauth_session preserves data" do
      keypair = DPoP.generate_keypair()
      expires = DateTime.utc_now() |> DateTime.add(1, :hour) |> DateTime.truncate(:microsecond)

      original = %OAuth.Session{
        did: "did:plc:roundtrip",
        handle: "roundtrip.bsky.social",
        access_token: "rt_access",
        refresh_token: "rt_refresh",
        dpop_keypair: keypair,
        pds_url: "https://pds.roundtrip.com",
        auth_server_url: "https://auth.roundtrip.com",
        scope: "atproto transition:generic",
        expires_at: expires,
        auth_server_nonce: nil,
        resource_server_nonce: nil
      }

      # Convert and save
      attrs = Session.from_oauth_session(original)
      {:ok, saved} = %Session{} |> Session.changeset(attrs) |> Repo.insert()

      # Fetch and convert back
      fetched = Repo.get!(Session, saved.id)
      restored = Session.to_oauth_session(fetched)

      assert restored.did == original.did
      assert restored.handle == original.handle
      assert restored.access_token == original.access_token
      assert restored.refresh_token == original.refresh_token
      assert restored.pds_url == original.pds_url
      assert restored.auth_server_url == original.auth_server_url
      assert restored.scope == original.scope
      assert restored.expires_at == original.expires_at

      # Test keypair is functional
      {pk, jwk} = restored.dpop_keypair
      proof = DPoP.create_proof(pk, jwk, "GET", "https://test.com")
      assert is_binary(proof)
    end
  end

  describe "expired?/1" do
    test "returns false when expires_at is nil" do
      session = %Session{expires_at: nil}
      refute Session.expired?(session)
    end

    test "returns false when not expired" do
      future = DateTime.utc_now() |> DateTime.add(1, :hour)
      session = %Session{expires_at: future}
      refute Session.expired?(session)
    end

    test "returns true when expired" do
      past = DateTime.utc_now() |> DateTime.add(-1, :hour)
      session = %Session{expires_at: past}
      assert Session.expired?(session)
    end
  end

  describe "should_refresh?/1" do
    test "returns false when expires_at is nil" do
      session = %Session{expires_at: nil}
      refute Session.should_refresh?(session)
    end

    test "returns false when expires in more than 5 minutes" do
      future = DateTime.utc_now() |> DateTime.add(10, :minute)
      session = %Session{expires_at: future}
      refute Session.should_refresh?(session)
    end

    test "returns true when expires in less than 5 minutes" do
      soon = DateTime.utc_now() |> DateTime.add(3, :minute)
      session = %Session{expires_at: soon}
      assert Session.should_refresh?(session)
    end

    test "returns true when already expired" do
      past = DateTime.utc_now() |> DateTime.add(-1, :minute)
      session = %Session{expires_at: past}
      assert Session.should_refresh?(session)
    end
  end
end
