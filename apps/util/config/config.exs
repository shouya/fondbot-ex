import Config

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :util,
  time: [
    timezone: "Asia/Shanghai"
  ]
