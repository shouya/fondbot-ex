defmodule Manager.ExtStack do
  use GenServer

  def start_link(exts) do
    GenServer.start_link(__MODULE__, exts, name: __MODULE__)
  end

  @impl true
  @spec init([atom()]) :: {:ok, any()}
  def init(exts \\ []) do
    {:ok, exts}
  end

  @spec insert(atom) :: any()
  def insert(ext_mod) do
    GenServer.call(__MODULE__, {:insert, ext_mod})
  end

  def process_event(payload) do
    GenServer.cast(__MODULE__, {:event, payload})
  end

  @impl true
  def handle_cast({:event, payload}, exts) do
    traverse_exts(exts, payload)
    {:noreply, exts}
  end

  @impl true
  def handle_cast({:insert, ext_mod}, exts) do
    {:noreply, [ext_mod | exts]}
  end

  @spec traverse_exts(maybe_improper_list(), any()) :: :ok
  defp traverse_exts([], _), do: :ok

  defp traverse_exts([ext | exts], payload) do
    payload = Util.Telegram.remove_command_suffix(payload)
    case Extension.process_update(ext, payload) do
      :ok -> traverse_exts(exts, payload)
      :break -> :ok
    end
  end
end
