defmodule Extension.Store.Redis do
  use Supervisor

  @behaviour Extension.Store

  @conn_name :ext_store

  @impl true
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(_opts) do
    redis_uri = Application.fetch_env!(:extension, :redis_uri)

    children = [
      {Redix, {redis_uri, name: @conn_name}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @impl Extension.Store
  def save_state(ext, state) do
    serialized = :base64.encode(:erlang.term_to_binary(state))

    case Redix.command(@conn_name, ["SET", "STATE:#{ext}", serialized]) do
      {:ok, "OK"} -> :ok
      {:ok, other} -> {:error, other}
      {:error, err} -> {:error, err}
    end
  end

  @impl Extension.Store
  def load_state(ext) do
    case Redix.command(@conn_name, ["GET", "STATE:#{ext}"]) do
      {:ok, nil} ->
        :undef

      {:ok, binary} when is_binary(binary) ->
        deserialized = :erlang.binary_to_term(:base64.decode(binary))
        {:ok, deserialized}

      {:error, err} ->
        IO.inspect(err)
        {:error, err}
    end
  end
end
