defmodule PokeAround.AI.Ollama do
  @moduledoc """
  Client for interacting with the Ollama API.
  """

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

    case Req.post("#{url}/api/generate",
           json: %{model: model, prompt: prompt, stream: false},
           receive_timeout: @timeout,
           connect_options: [timeout: 5_000]
         ) do
      {:ok, %{status: 200, body: %{"response" => response}}} ->
        {:ok, response}

      {:ok, %{status: 200, body: %{"error" => error}}} ->
        {:error, error}

      {:ok, %{status: status, body: body}} ->
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

    case Req.get("#{url}/api/tags", receive_timeout: 5_000) do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  end

  @doc """
  List available models.
  """
  def list_models(opts \\ []) do
    url = opts[:url] || @default_url

    case Req.get("#{url}/api/tags", receive_timeout: 5_000) do
      {:ok, %{status: 200, body: %{"models" => models}}} ->
        {:ok, Enum.map(models, & &1["name"])}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
