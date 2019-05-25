defmodule Manager.MixProject do
  use Mix.Project

  def project do
    [
      app: :manager,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Manager.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:extension, in_umbrella: true},
      {:plug_cowboy, "~> 2.0"},
      {:jason, "~> 1.1"},
      {:sentry, "~> 7.0"},
      # {:nadia, github: "shouya/nadia"}
      {:nadia, path: "../../../nadia"}
    ]
  end
end
