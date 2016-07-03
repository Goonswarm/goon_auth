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
     applications: [:phoenix, :phoenix_html, :cowboy, :logger, :gettext,
                    :httpoison, :oauth2, :uuid, :eldap, :xmlrpc, :erlsom]]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(_),     do: ["lib", "web"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [{:phoenix, "~> 1.2"},
     {:phoenix_html, "~> 2.6"},
     {:phoenix_live_reload, "~> 1.0", only: :dev},
     {:gettext, "~> 0.11"},
     {:cowboy, "~> 1.0"},
     {:httpoison, "~> 0.9"},
     {:oauth2, "~> 0.5"},
     {:uuid, "~> 1.1"},
     {:erlsom, "~> 1.4"},
     {:xmlrpc, "~> 1.0"},
    ]
  end
end
