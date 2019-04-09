defmodule Manager.ExtStack do
  use GenServer

  defguardp is_event(t) when t in [:message, :callback, :inline_callback]

  @spec init([atom()]) :: {:ok, any()}
  def init(exts \\ []) do
    {:ok, exts}
  end

  @spec insert(atom) :: any()
  def insert(ext_mod) do
    GenServer.call(__MODULE__, {:insert, ext_mod})
  end

  def handle({event, payload}) do
    GenServer.cast(__MODULE__, {event, payload})
  end

  def handle_cast({event, payload}, _, exts) when is_event(event) do
    traverse_exts(exts, {event, payload})
    {:noreply, exts}
  end

  def handle_cast({:insert, ext_mod}, _, exts) do
    {:reply, [ext_mod | exts]}
  end

  @spec traverse_exts(maybe_improper_list(), any()) :: :ok
  defp traverse_exts([], _), do: :ok

  defp traverse_exts([ext | exts], message) do
    case apply(ext, :handle, [message]) do
      :ok -> traverse_exts(exts, message)
      :skip -> traverse_exts(exts, message)
      :break -> :ok
    end
  end
end
