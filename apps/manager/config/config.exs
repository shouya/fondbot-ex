use Mix.Config

config :nadia,
  token: System.get_env("FONDBOT_TOKEN")

config :manager,
  exts: [
    # Beware of the ordering!
    Extension.Guard,
    Extension.DevUtil,
    Extension.AFK,
    Extension.Weather,
    Extension.Reminder.Supervisor,
    Extension.Fetcher,
    Extension.Random
  ],
  updater: :poll

config :manager, :webhook,
  port: 9786,
  url: "https://7c857279.ngrok.io"

import_config "#{Mix.env()}.exs"
