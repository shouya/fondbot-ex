defmodule Manager.Updater.Webhook do
  defmodule Route do
    use Plug.Router

    plug(Plug.Parsers,
      parsers: [:json],
      pass: ["application/json"],
      json_decoder: Jason
    )

    plug(:match)
    plug(:dispatch)

    get "/" do
      send_resp(conn, 200, "OK")
    end

    post "/" do
      conn.params
      |> atomize_keys()
      |> List.wrap()
      |> Nadia.Parser.parse_result("getUpdates")
      |> Manager.Updater.dispatch_updates()

      send_resp(conn, 200, "OK")
    end

    match _ do
      send_resp(conn, 404, "OOPS")
    end

    defp atomize_keys(%{} = m) do
      Enum.map(m, fn {k, v} ->
        try do
          {String.to_existing_atom(k), atomize_keys(v)}
        rescue
          ArgumentError -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()
    end

    defp atomize_keys(l) when is_list(l) do
      Enum.map(l, &atomize_keys/1)
    end

    defp atomize_keys(x), do: x
  end

  use Supervisor

  def start_link(_) do
    Supervisor.start_link(__MODULE__, nil)
  end

  def init(_) do
    webhook_conf = Confex.get_env(:manager, :webhook, [])
    url = Keyword.fetch!(webhook_conf, :url)
    spawn(fn -> Nadia.set_webhook(url: url) end)

    children = [
      Plug.Cowboy.child_spec(
        scheme: :http,
        plug: Route,
        options: [port: Keyword.get(webhook_conf, :port, 9786)]
      )
    ]

    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.init(children, opts)
  end
end
