defmodule PokeAroundWeb.API.LinkControllerTest do
  use PokeAroundWeb.ConnCase, async: true

  alias PokeAround.Links

  describe "POST /api/links" do
    test "creates link with valid URL", %{conn: conn} do
      url = "https://example.com/test-#{System.unique_integer([:positive])}"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/links", %{url: url})

      assert %{"status" => "created", "id" => id, "message" => "Link saved!"} =
               json_response(conn, 201)

      assert is_integer(id)

      # Verify link was stored
      link = Links.get_link(id)
      assert link.url == url
    end

    test "stores optional title and description", %{conn: conn} do
      url = "https://example.com/with-meta-#{System.unique_integer([:positive])}"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/links", %{
          url: url,
          title: "Page Title",
          description: "Page description"
        })

      assert %{"status" => "created", "id" => id} = json_response(conn, 201)

      link = Links.get_link(id)
      assert link.title == "Page Title"
      assert link.description == "Page description"
    end

    test "handles single lang parameter", %{conn: conn} do
      url = "https://example.com/with-lang-#{System.unique_integer([:positive])}"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/links", %{url: url, lang: "en"})

      assert %{"status" => "created", "id" => id} = json_response(conn, 201)

      link = Links.get_link(id)
      assert link.langs == ["en"]
    end

    test "handles array of langs", %{conn: conn} do
      url = "https://example.com/multi-lang-#{System.unique_integer([:positive])}"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/links", %{url: url, lang: ["en", "es"]})

      assert %{"status" => "created", "id" => id} = json_response(conn, 201)

      link = Links.get_link(id)
      assert link.langs == ["en", "es"]
    end

    test "handles nil lang parameter", %{conn: conn} do
      url = "https://example.com/no-lang-#{System.unique_integer([:positive])}"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/links", %{url: url, lang: nil})

      assert %{"status" => "created", "id" => id} = json_response(conn, 201)

      link = Links.get_link(id)
      assert link.langs == []
    end

    test "handles empty string lang parameter", %{conn: conn} do
      url = "https://example.com/empty-lang-#{System.unique_integer([:positive])}"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/links", %{url: url, lang: ""})

      assert %{"status" => "created", "id" => id} = json_response(conn, 201)

      link = Links.get_link(id)
      assert link.langs == []
    end

    test "returns exists status for duplicate URLs", %{conn: conn} do
      url = "https://example.com/duplicate-#{System.unique_integer([:positive])}"

      # First request creates the link
      conn1 =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/links", %{url: url})

      assert %{"status" => "created"} = json_response(conn1, 201)

      # Second request returns exists
      conn2 =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/links", %{url: url})

      assert %{"status" => "exists", "message" => "Link already saved"} =
               json_response(conn2, 200)
    end

    test "returns bad request when url is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/links", %{title: "No URL"})

      assert %{"status" => "error", "message" => "url is required"} =
               json_response(conn, 400)
    end

    test "sets default score of 50", %{conn: conn} do
      url = "https://example.com/score-test-#{System.unique_integer([:positive])}"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/links", %{url: url})

      assert %{"status" => "created", "id" => id} = json_response(conn, 201)

      link = Links.get_link(id)
      assert link.score == 50
    end
  end
end
