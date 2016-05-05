defmodule GoonAuth.RegistrationController do
  @moduledoc "Allow account registration based on EVE CREST"
  use GoonAuth.Web, :controller
  alias GoonAuth.EVE.{Auth, CREST}

  @doc """
  Render main registration page.

  If the user has not yet started a registration session, they will be presented
  with the SSO login button.

  If an active registration session exists we request a password and email address.
  """
  def register(conn, _params) do
    case get_registration_session(conn) do
      :no_session     -> redirect(conn, to: "/register/start")
      {:ok, _session} -> redirect(conn, to: "/register/form")
    end
  end

  @doc "Registration start page with SSO login button"
  def start(conn, _params) do
    # Drop session in case there was an old one present
    configure_session(conn, drop: true)
    oauth_url = Auth.authorize_url!
    render(conn, "landing.html", oauth_url: oauth_url)
  end

  @doc "Show the registration form requesting password and email address"
  def registration_form(conn, session) do
    case get_session(conn, :name) do
      nil -> redirect(conn, to: "/register/start")
      name ->
        render(conn, "registration_form.html", name: name)
    end
  end

  @doc "Receives a filled-in registration form and processes it"
  def process_registration(conn, params) do
  end

  @doc """
  Catches CREST OAuth token after a successful login.
  In order to let the user proceed with registering, we need to temporarily
  store the token and give the client a session.

  Registration sessions will expire after five minutes.
  """
  def catch_token(conn, params) do
    token = Auth.get_token!(code: params["code"])
    character_id = CREST.get_character_id(token)
    character = CREST.get_character(token, character_id)

    # Store registration session
    reg_id = UUID.uuid4()
    now = :os.system_time(:seconds)
    :ets.insert(:registrations, {reg_id, token, character, now})
    conn = put_session(conn, :reg_id, reg_id)
    conn = put_session(conn, :name, character[:name])

    # Send on to registration form
    redirect(conn, to: "/register/form")
  end

  # Private helper functions

  # Retrieve the registration session and data or return :no_session
  def get_registration_session(conn) do
    reg_id = get_session(conn, :reg_id)
    result = :ets.lookup(:registrations, reg_id)
    case result do
      []        -> :no_session
      [session] -> {:ok, session}
    end
  end
end
