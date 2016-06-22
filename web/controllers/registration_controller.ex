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
      {:ok, status} -> begin_registration(conn, status, token, character)
      {:error, :already_registered} ->
        update_token(character[:name], token)
        reject_registration(conn, :already_registered, character[:name])
      {:error, err} -> reject_registration(conn, err, character[:name])
    end
  end

  @doc "Verifies that a corp exists in LDAP and is eligible for auth"
  def eligible?(char) do
    {:ok, conn} = LDAP.connect
    corp = LDAP.retrieve(conn, char[:corporation], :corp)
    user = LDAP.retrieve(conn, char[:name], :user)
    :eldap.close(conn)

    # Corp exists, user doesn't -> eligible
    # User exists -> double registration
    # Corp doesn't exist -> ineligible
    case {corp, user} do
      {_corp, {:ok, _user}}      -> {:error, :already_registered}
      {{:ok, _corp}, :not_found} -> {:ok, :eligible}
      {:not_found, _user}        -> {:ok, :can_apply}
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

  @doc "Show the application form for non-members"
  def application_form(conn, _params) do
    case get_session(conn, :name) do
      nil -> redirect(conn, to: "/register/start")
      name ->
        render(conn, "application_form.html", name: name)
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
      group: character[:group],
      pilotActive: character[:pilotActive],
      refresh_token: token.refresh_token,
      email: reg["email"],
      password: reg["password"]
    }

    process_registration(conn, user)
  end

  @doc "Finally write to LDAP and conclude registration"
  def process_registration(conn, user) do
    # Register user with LDAP
    Logger.info("Registering user #{user[:name]} (#{user[:corporation]}#{user[:group]})")
    :ok = LDAP.register_user(user)

    # Drop registration session and proceed to front page
    conn
    |> clear_session
    |> put_flash(:info, "Welcome to GoonSwarm! You can now log in to our services.")
    |> redirect(to: "/")
  end

  @doc "If a user is eligible, create a registration session and proceed"
  def begin_registration(conn, status, token, character) do
    # Store registration session
    reg_id = UUID.uuid4()
    now = :os.system_time(:seconds)
    conn = put_session(conn, :reg_id, reg_id)
    conn = put_session(conn, :name, character[:name])

    case status do
      :eligible  ->
        character = Map.put(character, :pilotActive, 'TRUE')
        :ets.insert(:registrations, {reg_id, token, character, now})
        redirect(conn, to: "/register/form")
      :can_apply ->
        # If the user is not in TDB, remove their current corporation and set the
        # applicants group.
        character = character
        |> Map.drop([:corporation])
        |> Map.put(:group, "applicants")
        |> Map.put(:pilotActive, 'FALSE')
        :ets.insert(:registrations, {reg_id, token, character, now})
        redirect(conn, to: "/register/apply")
    end
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

  @doc """
  If a user is already registered but we receive a new token for them, the token
  should be updated in LDAP.
  """
  def update_token(name, token) do
    refresh_token = :erlang.binary_to_list(token.refresh_token)
    Logger.info("Updating refresh token for user #{name}")
    {:ok, conn} = LDAP.connect_admin
    :ok = LDAP.replace_token(conn, name, refresh_token)
    :eldap.close(conn)
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
