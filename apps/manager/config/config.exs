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
  updater: :webhook

config :manager, :webhook,
  port: 9786,
  url: "https://7c857279.ngrok.io"

import_config "#{Mix.env()}.exs"
