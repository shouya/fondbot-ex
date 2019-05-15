defmodule Manager.Updater.Webhook do
  use Plug.Router

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Poison
  )

  get "/" do
    send_resp(conn, 200, "OK")
  end
end
