use Mix.Config

config :nadia,
  token: {:system, "FONDBOT_TOKEN"}

config :manager,
  exts: [
    # Beware of the ordering!
    Extension.Guard,
    Extension.DevUtil,
    Extension.AFK,
    Extension.Weather,
    Extension.Reminder.Builder,
    Extension.Reminder.Manager
  ],
  updater: :poll

config :manager, :webhook, port: 8976


# import_config "#{Mix.env()}.exs"
