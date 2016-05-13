defmodule GoonAuth do
  @moduledoc "Entrypoint module for the GoonAuth application"
  use Application
  require Logger

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    # Load secrets from a file
    load_secrets

    # Set up secret key
    set_secret_key

    # Set up ETS table used for registrations
    :ets.new(:registrations, [:named_table, :public, read_concurrency: true])

    children = [
      # Start the endpoint when the application starts
      supervisor(GoonAuth.Endpoint, []),
      # Start the "cleaner" process that removes old registrations
      worker(GoonAuth.Cleaner, [60])
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GoonAuth.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Tell Phoenix to update the endpoint configuration
  whenever the application is updated.
  """
  def config_change(changed, _new, removed) do
    GoonAuth.Endpoint.config_change(changed, removed)
    :ok
  end

  @doc """
  Load secrets configuration from an external file and add it to the application
  configuration. The external file should be in JSON format. An example is
  provided in the application README.
  """
  def load_secrets do
    path = Application.get_env(:goon_auth, :secrets_path, "")
    case File.read(path) do
      {:ok, file} ->
        Logger.info("Read secrets from #{path}")
        secrets = Poison.decode!(file, keys: :atoms)
        Enum.map(secrets, fn({secret, value}) ->
          Application.put_env(:goon_auth, secret, value)
        end)
      _ -> :ok
    end
  end

  @doc "Sets the Phoenix session secret key from secret configuration"
  def set_secret_key do
    endpoint_config = Application.get_env(:goon_auth, GoonAuth.Endpoint)
    secret_key = Application.get_env(:goon_auth, :phoenix_secret_key)
    new_config = Keyword.put(endpoint_config, :secret_key_base, secret_key)
    Application.put_env(:goon_auth, GoonAuth.Endpoint, new_config)
  end
end
