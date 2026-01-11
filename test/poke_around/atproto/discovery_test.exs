defmodule PokeAround.ATProto.DiscoveryTest do
  use ExUnit.Case, async: true

  alias PokeAround.ATProto.Discovery

  describe "fetch_resource_server_metadata/2" do
    test "returns metadata on success" do
      Req.Test.stub(Discovery, fn conn ->
        assert conn.request_path == "/.well-known/oauth-protected-resource"

        Req.Test.json(conn, %{
          "resource" => "https://pds.example.com",
          "authorization_servers" => ["https://auth.example.com"]
        })
      end)

      assert {:ok, metadata} =
               Discovery.fetch_resource_server_metadata(
                 "https://pds.example.com",
                 plug: {Req.Test, Discovery}
               )

      assert metadata["resource"] == "https://pds.example.com"
      assert metadata["authorization_servers"] == ["https://auth.example.com"]
    end

    test "trims trailing slash from PDS URL" do
      Req.Test.stub(Discovery, fn conn ->
        assert conn.host == "pds.example.com"
        Req.Test.json(conn, %{"resource" => "https://pds.example.com"})
      end)

      assert {:ok, _} =
               Discovery.fetch_resource_server_metadata(
                 "https://pds.example.com/",
                 plug: {Req.Test, Discovery}
               )
    end

    test "returns error on non-200 status" do
      Req.Test.stub(Discovery, fn conn ->
        Plug.Conn.send_resp(conn, 404, "")
      end)

      assert {:error, {:http_error, 404}} =
               Discovery.fetch_resource_server_metadata(
                 "https://pds.example.com",
                 plug: {Req.Test, Discovery}
               )
    end
  end

  describe "fetch_auth_server_metadata/2" do
    test "returns metadata on success" do
      Req.Test.stub(Discovery, fn conn ->
        assert conn.request_path == "/.well-known/oauth-authorization-server"

        Req.Test.json(conn, %{
          "issuer" => "https://auth.example.com",
          "authorization_endpoint" => "https://auth.example.com/authorize",
          "token_endpoint" => "https://auth.example.com/token",
          "pushed_authorization_request_endpoint" => "https://auth.example.com/par"
        })
      end)

      assert {:ok, metadata} =
               Discovery.fetch_auth_server_metadata(
                 "https://auth.example.com",
                 plug: {Req.Test, Discovery}
               )

      assert metadata["issuer"] == "https://auth.example.com"
      assert metadata["authorization_endpoint"] == "https://auth.example.com/authorize"
    end

    test "returns error on non-200 status" do
      Req.Test.stub(Discovery, fn conn ->
        Plug.Conn.send_resp(conn, 500, "")
      end)

      assert {:error, {:http_error, 500}} =
               Discovery.fetch_auth_server_metadata(
                 "https://auth.example.com",
                 plug: {Req.Test, Discovery}
               )
    end
  end

  describe "resolve_handle/3" do
    test "returns DID on success" do
      Req.Test.stub(Discovery, fn conn ->
        assert conn.request_path == "/xrpc/com.atproto.identity.resolveHandle"
        assert conn.query_string =~ "handle=test.bsky.social"

        Req.Test.json(conn, %{"did" => "did:plc:abc123"})
      end)

      assert {:ok, "did:plc:abc123"} =
               Discovery.resolve_handle(
                 "test.bsky.social",
                 "https://bsky.social",
                 plug: {Req.Test, Discovery}
               )
    end

    test "returns error on non-200 status" do
      Req.Test.stub(Discovery, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, Jason.encode!(%{"error" => "InvalidHandle"}))
      end)

      assert {:error, {:resolve_failed, 400, _body}} =
               Discovery.resolve_handle(
                 "invalid",
                 "https://bsky.social",
                 plug: {Req.Test, Discovery}
               )
    end

    test "uses default PDS URL when not specified" do
      Req.Test.stub(Discovery, fn conn ->
        assert conn.host == "bsky.social"
        Req.Test.json(conn, %{"did" => "did:plc:xyz"})
      end)

      assert {:ok, _} =
               Discovery.resolve_handle("test.bsky.social", "https://bsky.social", plug: {Req.Test, Discovery})
    end
  end

  describe "fetch_did_document/2" do
    test "fetches did:plc document from plc.directory" do
      Req.Test.stub(Discovery, fn conn ->
        assert conn.host == "plc.directory"
        assert conn.request_path == "/did:plc:abc123"

        Req.Test.json(conn, %{
          "id" => "did:plc:abc123",
          "service" => [
            %{"id" => "#atproto_pds", "serviceEndpoint" => "https://pds.example.com"}
          ]
        })
      end)

      assert {:ok, doc} =
               Discovery.fetch_did_document("did:plc:abc123", plug: {Req.Test, Discovery})

      assert doc["id"] == "did:plc:abc123"
    end

    test "fetches did:web document from domain" do
      Req.Test.stub(Discovery, fn conn ->
        assert conn.host == "example.com"
        assert conn.request_path == "/.well-known/did.json"

        Req.Test.json(conn, %{
          "id" => "did:web:example.com",
          "service" => []
        })
      end)

      assert {:ok, doc} =
               Discovery.fetch_did_document("did:web:example.com", plug: {Req.Test, Discovery})

      assert doc["id"] == "did:web:example.com"
    end

    test "returns error for unsupported DID method" do
      assert {:error, :unsupported_did_method} = Discovery.fetch_did_document("did:key:abc")
    end

    test "returns error on non-200 status" do
      Req.Test.stub(Discovery, fn conn ->
        Plug.Conn.send_resp(conn, 404, "")
      end)

      assert {:error, {:http_error, 404}} =
               Discovery.fetch_did_document("did:plc:notfound", plug: {Req.Test, Discovery})
    end
  end

  describe "get_pds_url/2" do
    test "extracts PDS URL from DID document" do
      Req.Test.stub(Discovery, fn conn ->
        Req.Test.json(conn, %{
          "id" => "did:plc:test123",
          "service" => [
            %{"id" => "#atproto_pds", "serviceEndpoint" => "https://my-pds.example.com"}
          ]
        })
      end)

      assert {:ok, "https://my-pds.example.com"} =
               Discovery.get_pds_url("did:plc:test123", req_opts: [plug: {Req.Test, Discovery}])
    end

    test "returns error when PDS service not found" do
      Req.Test.stub(Discovery, fn conn ->
        Req.Test.json(conn, %{
          "id" => "did:plc:nopds",
          "service" => [
            %{"id" => "#other_service", "serviceEndpoint" => "https://other.com"}
          ]
        })
      end)

      assert {:error, :pds_not_found} =
               Discovery.get_pds_url("did:plc:nopds", req_opts: [plug: {Req.Test, Discovery}])
    end

    test "returns error for invalid DID document" do
      Req.Test.stub(Discovery, fn conn ->
        Req.Test.json(conn, %{"id" => "did:plc:invalid"})
      end)

      assert {:error, :invalid_did_doc} =
               Discovery.get_pds_url("did:plc:invalid", req_opts: [plug: {Req.Test, Discovery}])
    end
  end

  describe "discover_auth_server/2" do
    test "combines resource and auth server metadata" do
      # Need to track which request we're handling
      test_pid = self()

      Req.Test.stub(Discovery, fn conn ->
        case conn.request_path do
          "/.well-known/oauth-protected-resource" ->
            send(test_pid, :resource_fetched)

            Req.Test.json(conn, %{
              "resource" => "https://pds.example.com",
              "authorization_servers" => ["https://auth.example.com"]
            })

          "/.well-known/oauth-authorization-server" ->
            send(test_pid, :auth_fetched)

            Req.Test.json(conn, %{
              "issuer" => "https://auth.example.com",
              "authorization_endpoint" => "https://auth.example.com/authorize",
              "token_endpoint" => "https://auth.example.com/token"
            })
        end
      end)

      assert {:ok, result} =
               Discovery.discover_auth_server(
                 "https://pds.example.com",
                 req_opts: [plug: {Req.Test, Discovery}]
               )

      assert result.pds_url == "https://pds.example.com"
      assert result.resource["authorization_servers"] == ["https://auth.example.com"]
      assert result.auth["issuer"] == "https://auth.example.com"

      # Verify both endpoints were called
      assert_received :resource_fetched
      assert_received :auth_fetched
    end

    test "returns error if resource server fetch fails" do
      Req.Test.stub(Discovery, fn conn ->
        Plug.Conn.send_resp(conn, 500, "")
      end)

      assert {:error, {:http_error, 500}} =
               Discovery.discover_auth_server(
                 "https://pds.example.com",
                 req_opts: [plug: {Req.Test, Discovery}]
               )
    end
  end
end
