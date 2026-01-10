defmodule PokeAround.ATProto.OAuth do
  @moduledoc """
  ATProto OAuth client implementation.

  Implements the full ATProto OAuth flow including:
  - PAR (Pushed Authorization Request)
  - PKCE (S256)
  - DPoP (Demonstrating Proof of Possession)
  - Token exchange and refresh

  ## Usage

      # Start authorization flow
      {:ok, auth_state} = OAuth.start_authorization("user.bsky.social", redirect_uri)
      # Redirect user to auth_state.authorization_url

      # Handle callback
      {:ok, session} = OAuth.exchange_code(auth_state, code)

      # Make authenticated requests
      {:ok, response} = OAuth.authenticated_request(session, :get, "/xrpc/...")

  """

  alias PokeAround.ATProto.{DPoP, PKCE, Discovery}

  require Logger

  @default_scope "atproto transition:generic"

  defmodule AuthState do
    @moduledoc "State for an in-progress authorization flow"
    defstruct [
      :state,
      :pkce_verifier,
      :dpop_keypair,
      :auth_server_metadata,
      :pds_url,
      :did,
      :authorization_url,
      :redirect_uri,
      :nonce
    ]
  end

  defmodule Session do
    @moduledoc "An authenticated OAuth session"
    defstruct [
      :did,
      :handle,
      :access_token,
      :refresh_token,
      :dpop_keypair,
      :pds_url,
      :auth_server_url,
      :scope,
      :expires_at,
      :auth_server_nonce,
      :resource_server_nonce
    ]
  end

  @doc """
  Start the OAuth authorization flow.

  ## Parameters

  - `handle_or_did` - User's handle (e.g., "user.bsky.social") or DID
  - `redirect_uri` - Your callback URL
  - `opts` - Optional parameters:
    - `:scope` - OAuth scopes (default: "atproto transition:generic")
    - `:client_id` - Your client_id URL (default from config)

  ## Returns

  `{:ok, %AuthState{}}` with `authorization_url` to redirect the user to.
  """
  def start_authorization(handle_or_did, redirect_uri, opts \\ []) do
    scope = opts[:scope] || @default_scope
    client_id = opts[:client_id] || get_client_id()

    with {:ok, did, pds_url} <- resolve_identity(handle_or_did),
         {:ok, server_meta} <- Discovery.discover_auth_server(pds_url),
         {:ok, auth_state} <- initiate_par(did, pds_url, server_meta, redirect_uri, client_id, scope) do
      {:ok, auth_state}
    end
  end

  @doc """
  Exchange an authorization code for tokens.

  ## Parameters

  - `auth_state` - The AuthState from start_authorization
  - `code` - Authorization code from callback
  - `returned_state` - State parameter from callback (for verification)

  ## Returns

  `{:ok, %Session{}}` on success.
  """
  def exchange_code(%AuthState{} = auth_state, code, returned_state) do
    # Verify state matches
    if returned_state != auth_state.state do
      {:error, :state_mismatch}
    else
      do_token_exchange(auth_state, code)
    end
  end

  @doc """
  Refresh an expired session.
  """
  def refresh_session(%Session{refresh_token: nil}), do: {:error, :no_refresh_token}

  def refresh_session(%Session{} = session) do
    token_endpoint = get_token_endpoint(session)
    {private_key, public_jwk} = session.dpop_keypair

    # Create DPoP proof
    dpop_proof = DPoP.create_proof(
      private_key,
      public_jwk,
      :post,
      token_endpoint,
      session.auth_server_nonce
    )

    body = %{
      "grant_type" => "refresh_token",
      "refresh_token" => session.refresh_token,
      "client_id" => get_client_id()
    }

    headers = [
      {"content-type", "application/x-www-form-urlencoded"},
      {"dpop", dpop_proof}
    ]

    case Req.post(token_endpoint, form: body, headers: headers, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: token_response, headers: resp_headers}} ->
        new_nonce = get_dpop_nonce(resp_headers)

        {:ok,
         %Session{
           session
           | access_token: token_response["access_token"],
             refresh_token: token_response["refresh_token"] || session.refresh_token,
             expires_at: calculate_expiry(token_response),
             auth_server_nonce: new_nonce || session.auth_server_nonce
         }}

      {:ok, %{status: 401, body: %{"error" => "use_dpop_nonce"}, headers: resp_headers}} ->
        # Retry with the provided nonce
        new_nonce = get_dpop_nonce(resp_headers)
        refresh_session(%{session | auth_server_nonce: new_nonce})

      {:ok, %{status: status, body: body}} ->
        {:error, {:token_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Make an authenticated request using the session.

  Automatically handles DPoP proof generation and nonce rotation.
  """
  def authenticated_request(%Session{} = session, method, url, opts \\ []) do
    {private_key, public_jwk} = session.dpop_keypair

    # Create DPoP proof with access token hash
    dpop_proof = DPoP.create_proof_with_ath(
      private_key,
      public_jwk,
      method,
      url,
      session.access_token,
      session.resource_server_nonce
    )

    headers =
      [
        {"authorization", "DPoP #{session.access_token}"},
        {"dpop", dpop_proof}
      ] ++ (opts[:headers] || [])

    req_opts =
      opts
      |> Keyword.drop([:headers])
      |> Keyword.put(:headers, headers)
      |> Keyword.put_new(:receive_timeout, 15_000)

    case apply(Req, method, [url, req_opts]) do
      {:ok, %{status: 401, body: %{"error" => "use_dpop_nonce"}, headers: resp_headers}} ->
        # Retry with the provided nonce
        new_nonce = get_dpop_nonce(resp_headers)
        updated_session = %{session | resource_server_nonce: new_nonce}
        authenticated_request(updated_session, method, url, opts)

      {:ok, %{headers: resp_headers} = response} ->
        # Update nonce if provided
        new_nonce = get_dpop_nonce(resp_headers)

        updated_session =
          if new_nonce do
            %{session | resource_server_nonce: new_nonce}
          else
            session
          end

        {:ok, response, updated_session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Serialize a session for storage.
  """
  def serialize_session(%Session{} = session) do
    %{
      "did" => session.did,
      "handle" => session.handle,
      "access_token" => session.access_token,
      "refresh_token" => session.refresh_token,
      "dpop_keypair" => DPoP.serialize_keypair(session.dpop_keypair),
      "pds_url" => session.pds_url,
      "auth_server_url" => session.auth_server_url,
      "scope" => session.scope,
      "expires_at" => session.expires_at && DateTime.to_iso8601(session.expires_at),
      "auth_server_nonce" => session.auth_server_nonce,
      "resource_server_nonce" => session.resource_server_nonce
    }
  end

  @doc """
  Deserialize a session from storage.
  """
  def deserialize_session(data) when is_map(data) do
    %Session{
      did: data["did"],
      handle: data["handle"],
      access_token: data["access_token"],
      refresh_token: data["refresh_token"],
      dpop_keypair: DPoP.deserialize_keypair(data["dpop_keypair"]),
      pds_url: data["pds_url"],
      auth_server_url: data["auth_server_url"],
      scope: data["scope"],
      expires_at: parse_datetime(data["expires_at"]),
      auth_server_nonce: data["auth_server_nonce"],
      resource_server_nonce: data["resource_server_nonce"]
    }
  end

  # Private functions

  defp resolve_identity("did:" <> _ = did) do
    case Discovery.get_pds_url(did) do
      {:ok, pds_url} -> {:ok, did, pds_url}
      error -> error
    end
  end

  defp resolve_identity(handle) do
    with {:ok, did} <- Discovery.resolve_handle(handle),
         {:ok, pds_url} <- Discovery.get_pds_url(did) do
      {:ok, did, pds_url}
    end
  end

  defp initiate_par(did, pds_url, server_meta, redirect_uri, client_id, scope) do
    auth_meta = server_meta.auth
    par_endpoint = auth_meta["pushed_authorization_request_endpoint"]
    auth_endpoint = auth_meta["authorization_endpoint"]

    # Generate security tokens
    state = generate_state()
    {pkce_verifier, pkce_challenge} = PKCE.generate()
    dpop_keypair = DPoP.generate_keypair()
    {private_key, public_jwk} = dpop_keypair

    # Create DPoP proof for PAR
    dpop_proof = DPoP.create_proof(private_key, public_jwk, :post, par_endpoint, nil)

    # PAR request body
    par_body = %{
      "client_id" => client_id,
      "response_type" => "code",
      "redirect_uri" => redirect_uri,
      "scope" => scope,
      "state" => state,
      "code_challenge" => pkce_challenge,
      "code_challenge_method" => "S256",
      "login_hint" => did
    }

    headers = [
      {"content-type", "application/x-www-form-urlencoded"},
      {"dpop", dpop_proof}
    ]

    case Req.post(par_endpoint, form: par_body, headers: headers, receive_timeout: 15_000) do
      {:ok, %{status: 201, body: %{"request_uri" => request_uri}, headers: resp_headers}} ->
        nonce = get_dpop_nonce(resp_headers)

        # Build authorization URL
        auth_url =
          auth_endpoint
          |> URI.parse()
          |> Map.put(:query, URI.encode_query(%{
            "client_id" => client_id,
            "request_uri" => request_uri
          }))
          |> URI.to_string()

        {:ok,
         %AuthState{
           state: state,
           pkce_verifier: pkce_verifier,
           dpop_keypair: dpop_keypair,
           auth_server_metadata: auth_meta,
           pds_url: pds_url,
           did: did,
           authorization_url: auth_url,
           redirect_uri: redirect_uri,
           nonce: nonce
         }}

      {:ok, %{status: 400, body: %{"error" => "use_dpop_nonce"}, headers: resp_headers}} ->
        # Retry with nonce
        nonce = get_dpop_nonce(resp_headers)
        initiate_par_with_nonce(did, pds_url, server_meta, redirect_uri, client_id, scope, dpop_keypair, state, pkce_verifier, nonce)

      {:ok, %{status: status, body: body}} ->
        Logger.error("PAR failed: #{status} #{inspect(body)}")
        {:error, {:par_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp initiate_par_with_nonce(did, pds_url, server_meta, redirect_uri, client_id, scope, dpop_keypair, state, pkce_verifier, nonce) do
    auth_meta = server_meta.auth
    par_endpoint = auth_meta["pushed_authorization_request_endpoint"]
    auth_endpoint = auth_meta["authorization_endpoint"]

    {private_key, public_jwk} = dpop_keypair
    pkce_challenge = PKCE.generate_challenge(pkce_verifier)

    dpop_proof = DPoP.create_proof(private_key, public_jwk, :post, par_endpoint, nonce)

    par_body = %{
      "client_id" => client_id,
      "response_type" => "code",
      "redirect_uri" => redirect_uri,
      "scope" => scope,
      "state" => state,
      "code_challenge" => pkce_challenge,
      "code_challenge_method" => "S256",
      "login_hint" => did
    }

    headers = [
      {"content-type", "application/x-www-form-urlencoded"},
      {"dpop", dpop_proof}
    ]

    case Req.post(par_endpoint, form: par_body, headers: headers, receive_timeout: 15_000) do
      {:ok, %{status: 201, body: %{"request_uri" => request_uri}, headers: resp_headers}} ->
        new_nonce = get_dpop_nonce(resp_headers)

        auth_url =
          auth_endpoint
          |> URI.parse()
          |> Map.put(:query, URI.encode_query(%{
            "client_id" => client_id,
            "request_uri" => request_uri
          }))
          |> URI.to_string()

        {:ok,
         %AuthState{
           state: state,
           pkce_verifier: pkce_verifier,
           dpop_keypair: dpop_keypair,
           auth_server_metadata: auth_meta,
           pds_url: pds_url,
           did: did,
           authorization_url: auth_url,
           redirect_uri: redirect_uri,
           nonce: new_nonce || nonce
         }}

      {:ok, %{status: status, body: body}} ->
        {:error, {:par_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_token_exchange(%AuthState{} = auth_state, code) do
    token_endpoint = auth_state.auth_server_metadata["token_endpoint"]
    {private_key, public_jwk} = auth_state.dpop_keypair

    dpop_proof = DPoP.create_proof(private_key, public_jwk, :post, token_endpoint, auth_state.nonce)

    body = %{
      "grant_type" => "authorization_code",
      "code" => code,
      "redirect_uri" => auth_state.redirect_uri,
      "client_id" => get_client_id(),
      "code_verifier" => auth_state.pkce_verifier
    }

    headers = [
      {"content-type", "application/x-www-form-urlencoded"},
      {"dpop", dpop_proof}
    ]

    case Req.post(token_endpoint, form: body, headers: headers, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: token_response, headers: resp_headers}} ->
        nonce = get_dpop_nonce(resp_headers)

        # Verify the sub matches expected DID
        if token_response["sub"] != auth_state.did do
          Logger.warning("DID mismatch: expected #{auth_state.did}, got #{token_response["sub"]}")
        end

        {:ok,
         %Session{
           did: token_response["sub"],
           handle: nil,
           access_token: token_response["access_token"],
           refresh_token: token_response["refresh_token"],
           dpop_keypair: auth_state.dpop_keypair,
           pds_url: auth_state.pds_url,
           auth_server_url: auth_state.auth_server_metadata["issuer"],
           scope: token_response["scope"],
           expires_at: calculate_expiry(token_response),
           auth_server_nonce: nonce,
           resource_server_nonce: nil
         }}

      {:ok, %{status: 400, body: %{"error" => "use_dpop_nonce"}, headers: resp_headers}} ->
        nonce = get_dpop_nonce(resp_headers)
        do_token_exchange(%{auth_state | nonce: nonce}, code)

      {:ok, %{status: status, body: body}} ->
        {:error, {:token_exchange_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_token_endpoint(%Session{auth_server_url: auth_url}) do
    # TODO: Could cache this, but for now just use convention
    "#{String.trim_trailing(auth_url, "/")}/oauth/token"
  end

  defp get_dpop_nonce(headers) do
    headers
    |> Enum.find(fn {k, _v} -> String.downcase(k) == "dpop-nonce" end)
    |> case do
      {_, nonce} -> nonce
      nil -> nil
    end
  end

  defp generate_state do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp calculate_expiry(%{"expires_in" => expires_in}) when is_integer(expires_in) do
    DateTime.utc_now() |> DateTime.add(expires_in, :second)
  end

  defp calculate_expiry(_), do: nil

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp get_client_id do
    Application.get_env(:poke_around, :atproto_client_id) ||
      raise "ATPROTO_CLIENT_ID not configured"
  end
end
