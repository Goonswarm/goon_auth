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
    get "/register", RegistrationController, :register
    get "/register/start", RegistrationController, :start
    get "/register/form", RegistrationController, :registration_form
    get "/register/crest-catch", RegistrationController, :catch_token
  end

  # Other scopes may use custom stacks.
  # scope "/api", GoonAuth do
  #   pipe_through :api
  # end
end
