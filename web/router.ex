defmodule GoonAuth.Router do
  use GoonAuth.Web, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", GoonAuth do
    pipe_through :browser # Use the default browser stack

    get "/", PageController, :index
    get "/welcome", PageController, :welcome

    # Login routes
    get "/login", LoginController, :login_form
    post "/login", LoginController, :handle_login
    get "/logout", LoginController, :handle_logout

    # Registration routes
    get "/register/start", RegistrationController, :start
    get "/register/form", RegistrationController, :registration_form
    get "/register/apply", RegistrationController, :application_form
    get "/register/crest-catch", RegistrationController, :catch_token
    post "/register", RegistrationController, :process_form

    # OAuth key upgrade route
    get "/key-upgrade", KeyController, :key_upgrade_page

    # Password change routes
    get "/change-password", PasswordChangeController, :password_change_form
    post "/change-password", PasswordChangeController, :change_password_handler

    # Jabber ping routes
    get "/ping", PingController, :ping_form
    post "/ping", PingController, :handle_ping

    # Group management routes
    get "/groups", GroupController, :group_list

    # nginx auth handler route
    get "/auth", AuthController, :handle_auth
  end

  # Other scopes may use custom stacks.
  # scope "/api", GoonAuth do
  #   pipe_through :api
  # end
end
