use Mix.Config

config :manager, updater: :webhook
config :manager, :webhook,
  port: 9786,
  url: System.get_env("WEBHOOK_URL")
