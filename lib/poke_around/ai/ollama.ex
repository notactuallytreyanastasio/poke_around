defmodule PokeAround.AI.Ollama do
  @moduledoc """
  HTTP client for Ollama local inference.

  ## Usage

      # Simple generation
      {:ok, response} = Ollama.generate("What is 2+2?", model: "llama3.2:3b")

      # Check availability
      Ollama.available?()
  """

  require Logger

  @default_url "http://localhost:11434"
  @default_model "llama3.2:3b"
  @timeout 120_000

  @doc """
  Check if Ollama is available.
  """
  def available? do
    url = get_url()

    case Req.get("#{url}/api/tags", receive_timeout: 5_000) do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  end

  @doc """
  List available models.
  """
  def list_models do
    url = get_url()

    case Req.get("#{url}/api/tags", receive_timeout: 5_000) do
      {:ok, %{status: 200, body: %{"models" => models}}} ->
        {:ok, Enum.map(models, & &1["name"])}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generate a response from Ollama.

  ## Options

  - `:model` - Model to use (default: "llama3.2:3b")
  - `:temperature` - Sampling temperature (default: model default)
  - `:system` - System prompt
  """
  def generate(prompt, opts \\ []) do
    url = get_url()
    model = opts[:model] || @default_model

    body = %{
      model: model,
      prompt: prompt,
      stream: false
    }

    body = if opts[:system], do: Map.put(body, :system, opts[:system]), else: body
    body = if opts[:temperature], do: Map.put(body, :options, %{temperature: opts[:temperature]}), else: body

    case Req.post("#{url}/api/generate", json: body, receive_timeout: @timeout) do
      {:ok, %{status: 200, body: %{"response" => response}}} ->
        {:ok, response}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Chat completion with messages.

  ## Options

  - `:model` - Model to use
  - `:temperature` - Sampling temperature
  """
  def chat(messages, opts \\ []) when is_list(messages) do
    url = get_url()
    model = opts[:model] || @default_model

    body = %{
      model: model,
      messages: messages,
      stream: false
    }

    body = if opts[:temperature], do: Map.put(body, :options, %{temperature: opts[:temperature]}), else: body

    case Req.post("#{url}/api/chat", json: body, receive_timeout: @timeout) do
      {:ok, %{status: 200, body: %{"message" => %{"content" => content}}}} ->
        {:ok, content}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_url do
    Application.get_env(:poke_around, __MODULE__, [])
    |> Keyword.get(:url, @default_url)
  end
end
