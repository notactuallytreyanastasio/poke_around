defmodule PokeAround.AI.Ollama do
  @moduledoc """
  Client for interacting with the Ollama API.
  """

  require Logger

  @default_url "http://localhost:11434"
  @default_model "qwen3:8b"
  @timeout 60_000

  @doc """
  Generate a completion from Ollama.

  Options:
  - `:model` - Model to use (default: qwen3:8b)
  - `:url` - Ollama API URL (default: http://localhost:11434)
  """
  def generate(prompt, opts \\ []) do
    model = opts[:model] || @default_model
    url = opts[:url] || @default_url

    body =
      Jason.encode!(%{
        model: model,
        prompt: prompt,
        stream: false
      })

    case :httpc.request(
           :post,
           {~c"#{url}/api/generate", [], ~c"application/json", body},
           [timeout: @timeout, connect_timeout: 5_000],
           []
         ) do
      {:ok, {{_, 200, _}, _headers, response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"response" => response}} ->
            {:ok, response}

          {:ok, %{"error" => error}} ->
            {:error, error}

          {:error, reason} ->
            {:error, {:json_decode, reason}}
        end

      {:ok, {{_, status, _}, _headers, body}} ->
        {:error, {:http_status, status, body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  @doc """
  Check if Ollama is available.
  """
  def available?(opts \\ []) do
    url = opts[:url] || @default_url

    case :httpc.request(:get, {~c"#{url}/api/tags", []}, [timeout: 5_000], []) do
      {:ok, {{_, 200, _}, _, _}} -> true
      _ -> false
    end
  end

  @doc """
  List available models.
  """
  def list_models(opts \\ []) do
    url = opts[:url] || @default_url

    case :httpc.request(:get, {~c"#{url}/api/tags", []}, [timeout: 5_000], []) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        case Jason.decode(body) do
          {:ok, %{"models" => models}} ->
            {:ok, Enum.map(models, & &1["name"])}

          error ->
            error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
