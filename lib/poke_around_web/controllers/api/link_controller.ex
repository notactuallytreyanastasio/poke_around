defmodule PokeAroundWeb.API.LinkController do
  use PokeAroundWeb, :controller

  alias PokeAround.Links

  @doc """
  Save a link from the bookmarklet.

  POST /api/links
  Body: { "url": "https://example.com", "title": "Page Title" }
  """
  def create(conn, %{"url" => url} = params) do
    attrs = %{
      url: url,
      title: params["title"],
      description: params["description"],
      score: 50  # Default score for user-submitted links
    }

    case Links.store_link(attrs) do
      {:ok, :exists} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "exists", message: "Link already saved"})

      {:ok, link} ->
        conn
        |> put_status(:created)
        |> json(%{status: "created", id: link.id, message: "Link saved!"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", errors: format_errors(changeset)})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{status: "error", message: "url is required"})
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
