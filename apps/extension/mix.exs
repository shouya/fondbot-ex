defmodule Extension.MixProject do
  use Mix.Project

  def project do
    [
      app: :extension,
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
      extra_applications: [:confex, :logger],
      mod: {Extension.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:util, in_umbrella: true},
      {:nanoid, "~> 2.0"},
      {:poison, "~> 3.1"},
      {:exactor, "~> 2.2"},
      {:nimble_parsec, "~> 0.5"},
      {:recon, "~> 2.5"},
      {:confex, "~> 3.4"},
      {:redix, "~> 1.1"},
      {:req, "~> 0.3"}
    ]
  end
end
