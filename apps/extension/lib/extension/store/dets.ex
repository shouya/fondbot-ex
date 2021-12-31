defmodule Extension.Store.Dets do
  use GenServer
  @table_name :fondbot_ext_store

  @behaviour Extension.Store

  @impl Extension.Store
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl Extension.Store
  def save_state(ext, state) do
    GenServer.call(__MODULE__, {:save, ext, state})
  end

  @impl Extension.Store
  def load_state(ext) do
    GenServer.call(__MODULE__, {:load, ext})
  end

  @impl GenServer
  def init(:ok) do
    data_file =
      :extension
      |> Application.get_env(:data_dir, "./data")
      |> Path.join("ext_store.db")
      |> String.to_charlist()

    data_file
    |> Path.dirname()
    |> File.mkdir_p()

    case :dets.open_file(@table_name, type: :set, file: data_file) do
      {:ok, _} -> {:ok, :ok}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:save, ext, state}, _, s) do
    :ok = :dets.insert(@table_name, {ext, state})
    {:reply, :ok, s}
  end

  @impl GenServer
  def handle_call({:load, ext}, _, s) do
    reply =
      case :dets.lookup(@table_name, ext) do
        [{_, value}] ->
          {:ok, value}

        [] ->
          :undef

        {:error, reason} ->
          {:error, reason}
      end

    {:reply, reply, s}
  end

  @impl GenServer
  def terminate(_, _) do
    :dets.close(@table_name)
  end
end
