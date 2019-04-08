defmodule Manager.ExtensionStack do
  use GenServer

  defguardp is_event(t) when t == :on_message or t == :on_callback

  def init(exts \\ []) do
    {:ok, exts}
  end

  def insert(ext_mod) do
    GenServer.call(__MODULE__, {:insert, ext_mod})
  end

  def handle_call({event, payload}, _, exts) when is_event(event) do
    traverse_exts(exts, {event, payload})
    {:reply, :ok, exts}
  end

  def handle_call({:insert, ext_mod}, _, exts) do
    {:reply, :ok, [ext_mod | exts]}
  end

  @spec traverse_exts(maybe_improper_list(), any()) :: :ok
  def traverse_exts([ext | exts], message) do
    case GenServer.call(ext, message) do
      :skip -> traverse_exts(exts, message)
      :ok -> traverse_exts(exts, message)
      :break -> :ok
    end
  end

  def traverse_exts([], _), do: :ok
end
