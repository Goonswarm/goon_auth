defmodule GoonAuth.RegistrationController do
  @moduledoc "Allow account registration based on EVE CREST"
  use GoonAuth.Web, :controller
  require Logger
  alias GoonAuth.EVE.{Auth, CREST}
  alias GoonAuth.LDAP

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
    conn = configure_session(conn, drop: true)
    oauth_url = Auth.authorize_url!
    render(conn, "landing.html", oauth_url: oauth_url)
  end

  @doc """
  Catches CREST OAuth token after a successful login.
  In order to let the user proceed with registering, we need to temporarily
  store the token and give the client a session.

  After user eligibility is verified, passes on to other verification functions.
  """
  def catch_token(conn, params) do
    token = Auth.get_token!(code: params["code"])
    character_id = CREST.get_character_id(token)
    character = CREST.get_character(token, character_id)

    case eligible?(character) do
      {:ok, :eligible} -> begin_registration(conn, token, character)
      {:error, err}    -> reject_registration(conn, err, character[:name])
    end
  end

  @doc "Verifies that a corp exists in LDAP and is eligible for auth"
  def eligible?(char) do
    corp = LDAP.retrieve(char[:corporation], :corp)
    user = LDAP.retrieve(char[:name], :user)
    # Corp exists, user doesn't -> eligible
    # User exists -> double registration
    # Corp doesn't exist -> ineligible
    case {corp, user} do
      {{:ok, _corp}, :not_found} -> {:ok, :eligible}
      {_corp, {:ok, _user}}      -> {:error, :already_registered}
      {:not_found, _user}        -> {:error, :ineligible}
    end
  end

  @doc "Show the registration form requesting password and email address"
  def registration_form(conn, _params) do
    case get_session(conn, :name) do
      nil -> redirect(conn, to: "/register/start")
      name ->
        render(conn, "registration_form.html", name: name)
    end
  end


  @doc """
  Receives a filled in registration form, validates the registration session
  and passes on to the next step
  """
  def validate_registration(conn, params) do
    case get_registration_session(conn) do
      :no_session -> redirect(conn, to: "/register/start")
      {:ok, {_id, token, character, time}} ->
        # Perform registration validations
        reg = params["registration"]
        form_ok = Enum.all?([reg["email"], reg["password"], reg["confirm"]])
        long_pass = String.length(reg["password"]) >= 8
        pass_match = reg["password"] == reg["confirm"]

        # Check that the session is still valid
        now = :os.system_time(:seconds)
        session_valid = (now - time) <= 500

        good_to_go? = form_ok and long_pass and pass_match and session_valid

        # Send the user on if everything is fine
        if good_to_go? do
          prepare_registration(conn, reg, token, character)
        else
          conn
          |> put_flash(:error, "Please try to fill the form in correctly!")
          |> register(params)
        end
    end
  end

  @doc """
  Consolidates the different values needed for registering and checks for double-
  registrations.
  """
  def prepare_registration(conn, reg, token, character) do
    # Extract the necessary fields out of what we have
    user = %{
      name: character[:name],
      corporation: character[:corporation],
      refresh_token: token.refresh_token,
      email: reg["email"],
      password: reg["password"]
    }

    process_registration(conn, user)
  end

  @doc "Finally write to LDAP and conclude registration"
  def process_registration(conn, user) do
    # Register user with LDAP
    Logger.info("Registering user #{user[:name]}")
    :ok = LDAP.register_user(user)

    # Drop registration session and proceed to front page
    conn
    |> clear_session
    |> put_flash(:info, "Welcome to GoonSwarm! You can now log in to our services.")
    |> redirect(to: "/")
  end

  @doc "If a user is eligible, create a registration session and proceed"
  def begin_registration(conn, token, character) do
    # Store registration session
    reg_id = UUID.uuid4()
    now = :os.system_time(:seconds)
    :ets.insert(:registrations, {reg_id, token, character, now})
    conn = put_session(conn, :reg_id, reg_id)
    conn = put_session(conn, :name, character[:name])

    # Send on to registration form
    redirect(conn, to: "/register/form")
  end

  @doc """
  Sends away users that aren't eligible for signup or that have already
  registered an account.
  """
  def reject_registration(conn, err, name) do
    # I want :frogout: here, but flashes are currently escaped.
    #getout = "<img src=\"/images/getout.gif\" alt=\":getout\">"
    message =
      case err do
        :ineligible -> "#{name} is not a member of [OHGOD] :getout:"
        :already_registered -> "#{name} already has an account :colbert:"
      end

    conn
    |> clear_session
    |> put_flash(:error, message)
    |> redirect(to: "/")
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
