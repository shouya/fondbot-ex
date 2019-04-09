use Mix.Config

config :nadia,
  token: {:system, "FONDBOT_TOKEN"}

config :manager,
  exts: [
    # Beware of the ordering!
    Extension.AFK
  ]

# import_config "#{Mix.env()}.exs"
