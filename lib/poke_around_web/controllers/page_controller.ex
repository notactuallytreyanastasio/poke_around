defmodule PokeAroundWeb.PageController do
  use PokeAroundWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
