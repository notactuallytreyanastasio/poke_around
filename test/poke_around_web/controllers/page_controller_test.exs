defmodule PokeAroundWeb.PageControllerTest do
  use PokeAroundWeb.ConnCase

  test "GET / serves StumbleLive", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "poke_around"
  end
end
