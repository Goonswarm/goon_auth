defmodule GoonAuth.Mixfile do
  use Mix.Project

  def project do
    [app: :goon_auth,
     version: "0.0.1",
     elixir: "~> 1.0",
     elixirc_paths: elixirc_paths(Mix.env),
     compilers: [:phoenix, :gettext] ++ Mix.compilers,
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [mod: {GoonAuth, []},
     applications: [:cowboy, :ecto, :eldap, :erlsom, :gettext, :httpoison,
                    :logger, :oauth2, :phoenix, :phoenix_html, :sweet_xml,
                    :timex, :xmlrpc]]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(_),     do: ["lib", "web"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:cowboy, "~> 1.0"},
      {:ecto, "~> 2.0"},
      {:erlsom, "~> 1.4"},
      {:gettext, "~> 0.11"},
      {:httpoison, "~> 0.9"},
      {:oauth2, "~> 0.5"},
      {:phoenix, "~> 1.2"},
      {:phoenix_html, "~> 2.6"},
      {:phoenix_live_reload, "~> 1.0", only: :dev},
      {:sweet_xml, "~> 0.6.1"},
      {:timex, "~> 2.2"},
      {:xmlrpc, "~> 1.0"},
    ]
  end
end
