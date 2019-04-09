defmodule Manager.ExtStack do
  use GenServer

  defguardp is_event(t) when t in [:message, :callback, :inline_callback]

  @spec init([atom()]) :: {:ok, any()}
  def init(exts \\ []) do
    exts |> Enum.each(&load_ext_conf/1)
    {:ok, exts}
  end

  @spec insert(atom) :: any()
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
  defp traverse_exts([ext | exts], message) do
    case apply(ext, :on, [message]) do
      :ok -> traverse_exts(exts, message)
      :skip -> traverse_exts(exts, message)
      :break -> :ok
    end
  end

  defp traverse_exts([], _), do: :ok

  defp load_ext_conf(ext) do
    GenServer.call(ext, :load_conf)
  end
end
