defmodule GoonAuth.RegistrationController do
  @moduledoc "Allow account registration based on EVE CREST"
  use GoonAuth.Web, :controller
  require Logger
  alias GoonAuth.EVE.{Auth, CREST}
  alias GoonAuth.LDAP

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
    char_id = CREST.get_character_id(token)
    character = CREST.get_character(token, char_id)
    name = character[:name]

    case eligible?(character) do
      {:ok, status} ->
        begin_registration(conn, status, token, name, char_id)
      {:error, :already_registered} ->
        update_token(name, token)
        reject_registration(conn, :already_registered, name)
      {:error, err} -> reject_registration(conn, err, name)
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
  and passes on to the next step.
  """
  def process_form(conn, params) do
    # Perform registration validations
    status = get_session(conn, :status)
    reg = params["registration"]
    form_ok = Enum.all?([reg["email"], reg["password"], reg["confirm"]])
    long_pass = String.length(reg["password"]) >= 8
    pass_match = reg["password"] == reg["confirm"]

    good_to_go? = form_ok and long_pass and pass_match

    # Send the user on if everything is fine
    if good_to_go? do
      prepare_registration(conn, reg)
    else
      conn
      |> put_flash(:error, "Please try to fill the form in correctly!")
      |> redirect(to: form_url(status))
    end
  end

  @doc """
  Retrieves all necessary information about the character being registered and
  configures applicant / member status before processing the registration.
  """
  def prepare_registration(conn, reg) do
    token   = get_session(conn, :token)
    char_id = get_session(conn, :char_id)
    status  = get_session(conn, :status)
    character = token
    |> CREST.get_character(char_id)
    |> prepare_character(status)

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

  # Eligible characters have their status set to active
  defp prepare_character(character, :eligible) do
    Map.put(character, :pilotActive, 'TRUE')
  end
  # Applicants have their current corporation removed and the applicant group
  # set. Applicants will not be marked as active users.
  defp prepare_character(character, :can_apply) do
    character
    |> Map.delete(:corporation)
    |> Map.put(:group, "applicants")
    |> Map.put(:pilotActive, 'FALSE')
  end

  @doc "Finally write to LDAP and conclude registration"
  def process_registration(conn, user) do
    # Register user with LDAP
    name = user[:name]
    Logger.info("Registering user #{name} (#{user[:corporation]}#{user[:group]})")
    :ok = LDAP.register_user(user)

    # Drop registration session and proceed to front page
    conn
    |> clear_session
    |> put_session(:user, name)
    |> redirect(to: "/welcome")
  end

  @doc """
  Redirects to the correct registration form after adding registration information
  to the user's session.
  """
  def begin_registration(conn, status, token, name, char_id) do
    conn
    |> put_session(:status, status)
    |> put_session(:token, token)
    |> put_session(:name, name)
    |> put_session(:char_id, char_id)
    |> redirect(to: form_url(status))
  end

  # Returns the correct registration form URL based on the registration status
  defp form_url(:eligible), do: "/register/form"
  defp form_url(:can_apply), do: "/register/apply"

  @doc """
  Sends away users that aren't eligible for signup or that have already
  registered an account.
  """
  def reject_registration(conn, err, name) do
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
end
