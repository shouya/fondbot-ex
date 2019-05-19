use Mix.Config

config :manager, updater: :webhook
config :manager, :webhook,
  port: 9786,
  url: {:system, "WEBHOOK_URL"}
