defmodule PokeAroundWeb.ATProtoAuthControllerTest do
  use PokeAroundWeb.ConnCase, async: true

  alias PokeAround.ATProto.{DPoP, Session}
  alias PokeAround.Repo

  describe "GET /auth/bluesky/callback" do
    test "returns error when callback params are missing", %{conn: conn} do
      conn = get(conn, "/auth/bluesky/callback")

      # Should redirect to home with error flash (non-popup mode)
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid callback parameters."
    end

    test "returns error when session state is missing", %{conn: conn} do
      # Simulate callback with code but no auth_state in session
      conn = get(conn, "/auth/bluesky/callback", code: "test_code", state: "test_state")

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Session expired. Please try again."
    end

    test "returns error in popup mode when params missing", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{auth_popup: true})
        |> get("/auth/bluesky/callback")

      # In popup mode, returns HTML with error message
      assert html_response(conn, 200) =~ "Invalid callback parameters."
      assert html_response(conn, 200) =~ "atproto_auth_error"
    end

    test "returns error in popup mode when session expired", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{auth_popup: true})
        |> get("/auth/bluesky/callback", code: "test_code", state: "test_state")

      assert html_response(conn, 200) =~ "Session expired"
      assert html_response(conn, 200) =~ "atproto_auth_error"
    end
  end

  describe "DELETE /auth/logout" do
    test "clears session and redirects", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{user_did: "did:plc:logout-test"})
        |> delete("/auth/logout")

      assert redirected_to(conn) == "/"
      # Session should be cleared
      assert get_session(conn, :user_did) == nil
    end

    test "deletes session from database if exists", %{conn: conn} do
      # Create a session in the database
      keypair = DPoP.generate_keypair()
      serialized = keypair |> DPoP.serialize_keypair() |> Jason.encode!()

      {:ok, db_session} =
        %Session{}
        |> Session.changeset(%{
          user_did: "did:plc:db-logout-test",
          dpop_keypair: serialized,
          pds_url: "https://pds.example.com"
        })
        |> Repo.insert()

      conn =
        conn
        |> init_test_session(%{user_did: "did:plc:db-logout-test"})
        |> delete("/auth/logout")

      assert redirected_to(conn) == "/"

      # Session should be deleted from database
      assert Repo.get(Session, db_session.id) == nil
    end

    test "handles logout gracefully when no session exists", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> delete("/auth/logout")

      # Should still redirect without error
      assert redirected_to(conn) == "/"
    end
  end
end
