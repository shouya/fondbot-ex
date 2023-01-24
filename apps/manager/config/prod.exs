import Config

config :manager, :updater, :webhook
config :manager, :webhook,
  ip: {0, 0, 0, 0},
  port: 9786,
  url: {:system, "WEBHOOK_URL"}
