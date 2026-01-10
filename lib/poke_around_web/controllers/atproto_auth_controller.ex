defmodule PokeAroundWeb.ATProtoAuthController do
  @moduledoc """
  Handles ATProto OAuth authentication flow.

  Endpoints:
  - GET /auth/bluesky - Initiate login
  - GET /auth/bluesky/callback - OAuth callback
  - DELETE /auth/logout - End session
  """

  use PokeAroundWeb, :controller

  alias PokeAround.ATProto.OAuth
  alias PokeAround.ATProto.Session, as: SessionSchema
  alias PokeAround.Repo

  require Logger

  @doc """
  Initiate the OAuth login flow.

  Query params:
  - `handle` - User's Bluesky handle (optional, can enter on Bluesky side)
  - `popup` - If "true", renders a minimal popup-friendly page
  """
  def login(conn, params) do
    handle = params["handle"]
    is_popup = params["popup"] == "true"
    redirect_uri = callback_url(conn)

    # Store popup mode in session for callback
    conn = put_session(conn, :auth_popup, is_popup)

    case initiate_auth(handle, redirect_uri) do
      {:ok, auth_state} ->
        # Store auth state in session
        conn
        |> put_session(:auth_state, serialize_auth_state(auth_state))
        |> redirect(external: auth_state.authorization_url)

      {:error, reason} ->
        Logger.error("OAuth initiation failed: #{inspect(reason)}")

        if is_popup do
          conn
          |> put_status(400)
          |> json(%{error: "auth_failed", message: "Failed to start authentication"})
        else
          conn
          |> put_flash(:error, "Failed to start authentication. Please try again.")
          |> redirect(to: ~p"/")
        end
    end
  end

  @doc """
  Handle the OAuth callback.

  Query params from authorization server:
  - `code` - Authorization code
  - `state` - State token for verification
  - `iss` - Issuer URL
  """
  def callback(conn, %{"code" => code, "state" => state} = _params) do
    is_popup = get_session(conn, :auth_popup) || false
    auth_state_data = get_session(conn, :auth_state)

    cond do
      is_nil(auth_state_data) ->
        handle_callback_error(conn, is_popup, "Session expired. Please try again.")

      true ->
        auth_state = deserialize_auth_state(auth_state_data)

        case OAuth.exchange_code(auth_state, code, state) do
          {:ok, oauth_session} ->
            # Persist session to database
            case save_session(oauth_session) do
              {:ok, _db_session} ->
                conn
                |> delete_session(:auth_state)
                |> delete_session(:auth_popup)
                |> put_session(:user_did, oauth_session.did)
                |> handle_callback_success(is_popup, oauth_session)

              {:error, reason} ->
                Logger.error("Failed to save session: #{inspect(reason)}")
                handle_callback_error(conn, is_popup, "Failed to save session.")
            end

          {:error, :state_mismatch} ->
            handle_callback_error(conn, is_popup, "Security validation failed. Please try again.")

          {:error, reason} ->
            Logger.error("Token exchange failed: #{inspect(reason)}")
            handle_callback_error(conn, is_popup, "Authentication failed. Please try again.")
        end
    end
  end

  def callback(conn, _params) do
    is_popup = get_session(conn, :auth_popup) || false
    handle_callback_error(conn, is_popup, "Invalid callback parameters.")
  end

  @doc """
  Log out and end the session.
  """
  def logout(conn, _params) do
    user_did = get_session(conn, :user_did)

    # Delete from database
    if user_did do
      case Repo.get_by(SessionSchema, user_did: user_did) do
        nil -> :ok
        session -> Repo.delete(session)
      end
    end

    conn
    |> clear_session()
    |> redirect(to: ~p"/")
  end

  # Private functions

  defp initiate_auth(nil, redirect_uri) do
    # No handle provided - user will enter on Bluesky side
    # We need a default PDS to start with
    OAuth.start_authorization("bsky.social", redirect_uri)
  end

  defp initiate_auth(handle, redirect_uri) do
    OAuth.start_authorization(handle, redirect_uri)
  end

  defp callback_url(_conn) do
    PokeAroundWeb.Endpoint.url() <> "/auth/bluesky/callback"
  end

  defp save_session(oauth_session) do
    attrs = SessionSchema.from_oauth_session(oauth_session)

    case Repo.get_by(SessionSchema, user_did: oauth_session.did) do
      nil ->
        %SessionSchema{}
        |> SessionSchema.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> SessionSchema.changeset(attrs)
        |> Repo.update()
    end
  end

  defp handle_callback_success(conn, true, oauth_session) do
    # Popup mode - render JS that posts message to opener and closes
    html(conn, """
    <!DOCTYPE html>
    <html>
    <head><title>Login Successful</title></head>
    <body>
      <script>
        if (window.opener) {
          window.opener.postMessage({
            type: 'atproto_auth_success',
            did: '#{oauth_session.did}'
          }, '*');
          window.close();
        } else {
          window.location.href = '/';
        }
      </script>
      <p>Login successful! This window should close automatically.</p>
      <p><a href="/">Click here if it doesn't close</a></p>
    </body>
    </html>
    """)
  end

  defp handle_callback_success(conn, false, _oauth_session) do
    conn
    |> put_flash(:info, "Successfully logged in with Bluesky!")
    |> redirect(to: ~p"/")
  end

  defp handle_callback_error(conn, true, message) do
    # Popup mode - render JS that posts error to opener
    html(conn, """
    <!DOCTYPE html>
    <html>
    <head><title>Login Failed</title></head>
    <body>
      <script>
        if (window.opener) {
          window.opener.postMessage({
            type: 'atproto_auth_error',
            error: '#{String.replace(message, "'", "\\'")}'
          }, '*');
          window.close();
        } else {
          window.location.href = '/';
        }
      </script>
      <p>#{message}</p>
      <p><a href="/">Return to PokeAround</a></p>
    </body>
    </html>
    """)
  end

  defp handle_callback_error(conn, false, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/")
  end

  defp serialize_auth_state(auth_state) do
    %{
      "state" => auth_state.state,
      "pkce_verifier" => auth_state.pkce_verifier,
      "dpop_keypair" => PokeAround.ATProto.DPoP.serialize_keypair(auth_state.dpop_keypair),
      "auth_server_metadata" => auth_state.auth_server_metadata,
      "pds_url" => auth_state.pds_url,
      "did" => auth_state.did,
      "redirect_uri" => auth_state.redirect_uri,
      "nonce" => auth_state.nonce
    }
  end

  defp deserialize_auth_state(data) do
    %OAuth.AuthState{
      state: data["state"],
      pkce_verifier: data["pkce_verifier"],
      dpop_keypair: PokeAround.ATProto.DPoP.deserialize_keypair(data["dpop_keypair"]),
      auth_server_metadata: data["auth_server_metadata"],
      pds_url: data["pds_url"],
      did: data["did"],
      authorization_url: nil,
      redirect_uri: data["redirect_uri"],
      nonce: data["nonce"]
    }
  end
end
