defmodule PokeAround.ATProto.Discovery do
  @moduledoc """
  ATProto server discovery and identity resolution.

  Handles:
  - PDS resource server metadata
  - Authorization server metadata
  - Handle to DID resolution
  - DID document fetching
  """

  require Logger

  @resource_server_path "/.well-known/oauth-protected-resource"
  @auth_server_path "/.well-known/oauth-authorization-server"

  @doc """
  Discover authorization server metadata from a PDS URL.

  First fetches the resource server metadata to find the authorization server,
  then fetches the authorization server metadata.

  ## Options

  - `:req_opts` - Additional options to pass to Req (for testing)
  """
  def discover_auth_server(pds_url, opts \\ []) do
    req_opts = opts[:req_opts] || []

    with {:ok, resource_meta} <- fetch_resource_server_metadata(pds_url, req_opts),
         auth_server_url <- get_auth_server_url(resource_meta),
         {:ok, auth_meta} <- fetch_auth_server_metadata(auth_server_url, req_opts) do
      {:ok, %{resource: resource_meta, auth: auth_meta, pds_url: pds_url}}
    end
  end

  @doc """
  Fetch resource server metadata from a PDS.

  ## Options

  Accepts Req options for testing (e.g., `plug: {Req.Test, __MODULE__}`)
  """
  def fetch_resource_server_metadata(pds_url, req_opts \\ []) do
    url = String.trim_trailing(pds_url, "/") <> @resource_server_path

    case Req.get(url, Keyword.merge([receive_timeout: 10_000], req_opts)) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetch authorization server metadata.

  ## Options

  Accepts Req options for testing (e.g., `plug: {Req.Test, __MODULE__}`)
  """
  def fetch_auth_server_metadata(auth_server_url, req_opts \\ []) do
    url = String.trim_trailing(auth_server_url, "/") <> @auth_server_path

    case Req.get(url, Keyword.merge([receive_timeout: 10_000], req_opts)) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Resolve a handle to a DID.

  Uses the com.atproto.identity.resolveHandle XRPC endpoint.

  ## Options

  Accepts Req options for testing as third argument.
  """
  def resolve_handle(handle, pds_url \\ "https://bsky.social", req_opts \\ []) do
    url = "#{String.trim_trailing(pds_url, "/")}/xrpc/com.atproto.identity.resolveHandle"

    case Req.get(url, Keyword.merge([params: [handle: handle], receive_timeout: 10_000], req_opts)) do
      {:ok, %{status: 200, body: %{"did" => did}}} ->
        {:ok, did}

      {:ok, %{status: status, body: body}} ->
        {:error, {:resolve_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get the PDS URL for a DID by fetching its DID document.

  ## Options

  - `:req_opts` - Additional options to pass to Req (for testing)
  """
  def get_pds_url(did, opts \\ []) do
    req_opts = opts[:req_opts] || []

    with {:ok, doc} <- fetch_did_document(did, req_opts),
         {:ok, pds} <- extract_pds_from_did_doc(doc) do
      {:ok, pds}
    end
  end

  @doc """
  Fetch a DID document.

  ## Options

  Accepts Req options for testing as second argument.
  """
  def fetch_did_document(did, req_opts \\ [])

  def fetch_did_document("did:plc:" <> _ = did, req_opts) do
    url = "https://plc.directory/#{did}"

    case Req.get(url, Keyword.merge([receive_timeout: 10_000], req_opts)) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch_did_document("did:web:" <> domain, req_opts) do
    # did:web:example.com -> https://example.com/.well-known/did.json
    url = "https://#{domain}/.well-known/did.json"

    case Req.get(url, Keyword.merge([receive_timeout: 10_000], req_opts)) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch_did_document(_, _req_opts), do: {:error, :unsupported_did_method}

  # Private functions

  defp get_auth_server_url(%{"authorization_servers" => [server | _]}), do: server
  defp get_auth_server_url(%{"authorization_servers" => server}) when is_binary(server), do: server
  defp get_auth_server_url(_), do: "https://bsky.social"

  defp extract_pds_from_did_doc(%{"service" => services}) when is_list(services) do
    case Enum.find(services, fn s -> s["id"] == "#atproto_pds" end) do
      %{"serviceEndpoint" => endpoint} -> {:ok, endpoint}
      _ -> {:error, :pds_not_found}
    end
  end

  defp extract_pds_from_did_doc(_), do: {:error, :invalid_did_doc}
end
