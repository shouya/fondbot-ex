import Config

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
    Extension.Reminder.Manager,
    Extension.Fetcher,
    Extension.Random,
    Extension.Cleanser
  ],
  extra_supervisors: [
    Extension.Reminder.Supervisor
  ],
  updater: :poll

config :manager, :webhook,
  ip: {127, 0, 0, 1},
  port: 9786,
  url: "https://7c857279.ngrok.io"

import_config "#{Mix.env()}.exs"
