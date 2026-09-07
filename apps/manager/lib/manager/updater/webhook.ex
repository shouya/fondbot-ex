defmodule Manager.Updater.Webhook do
  require Logger

  @moduledoc """
  Receives updates over a Telegram webhook.

  The endpoint is reachable by anyone who can reach the port, so every
  update must carry the secret token registered with setWebhook. Without
  it a forged update can claim any sender id and pass Extension.Guard.
  """

  defmodule Route do
    use Plug.Router
    require Logger

    @secret_header "x-telegram-bot-api-secret-token"

    plug(:authenticate)

    plug(Plug.Parsers,
      parsers: [:json],
      pass: ["application/json"],
      length: 1_000_000,
      json_decoder: Jason
    )

    plug(:match)
    plug(:dispatch)

    @spec put_secret(binary()) :: :ok
    def put_secret(secret) when is_binary(secret) do
      :persistent_term.put({__MODULE__, :secret}, secret)
    end

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

    defp authenticate(%{method: "GET"} = conn, _opts), do: conn

    defp authenticate(conn, _opts) do
      secret = :persistent_term.get({__MODULE__, :secret})
      presented = Plug.Conn.get_req_header(conn, @secret_header)

      if Enum.any?(presented, &Plug.Crypto.secure_compare(&1, secret)) do
        conn
      else
        Logger.warning("Rejected a webhook request without a valid secret token")

        conn
        |> Plug.Conn.send_resp(401, "NOPE")
        |> Plug.Conn.halt()
      end
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
    webhook_conf = Application.get_env(:manager, :webhook, [])
    url = Keyword.fetch!(webhook_conf, :url)
    secret = configured_secret(webhook_conf) || generate_secret()
    Route.put_secret(secret)

    case Nadia.set_webhook(url: url, secret_token: secret) do
      :ok -> Logger.info("Webhook set to #{url}")
      {:error, e} -> raise "Unable to set webhook: #{inspect(e)}"
    end

    children = [
      Plug.Cowboy.child_spec(
        scheme: :http,
        plug: Route,
        options: [
          ip: Keyword.get(webhook_conf, :ip, {127, 0, 0, 1}),
          port: Keyword.get(webhook_conf, :port, 9786)
        ]
      )
    ]

    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.init(children, opts)
  end

  @spec configured_secret(Keyword.t()) :: binary() | nil
  defp configured_secret(conf) do
    case Keyword.get(conf, :secret_token) do
      token when is_binary(token) and byte_size(token) > 0 -> token
      _ -> nil
    end
  end

  # Telegram accepts 1-256 chars of A-Z, a-z, 0-9, _ and - as a secret token.
  defp generate_secret do
    Logger.info("No :secret_token configured, generating one for this run")
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
