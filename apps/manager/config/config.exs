use Mix.Config

config :nadia,
  token: {:system, "FONDBOT_TOKEN"}

config :manager,
  exts: [
    # Beware of the ordering!
    Extension.Guard,
    Extension.AFK,
    Extension.Weather,
    Extension.Reminder.Builder,
    Extension.Reminder.Manager
  ]

# import_config "#{Mix.env()}.exs"
