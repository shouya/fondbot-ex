defmodule Fondbot.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      version: "0.1.0"
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    [
      # {:edeliver, ">= 1.6.0"},
      {:distillery, "~> 2.0"}
    ]
  end

  defp releases() do
    [
      fondbot: [
        applications: [
          manager: :permanent,
          extension: :permanent,
          util: :permanent
        ]
      ]
    ]
  end
end
