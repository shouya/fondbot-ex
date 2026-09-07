defmodule Manager.ExtStack do
  use GenServer

  require Logger

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
  def handle_call({:insert, ext_mod}, _from, exts) do
    {:reply, :ok, [ext_mod | exts]}
  end

  @impl true
  # discard timeout messages
  def handle_info({ref, _content}, state) when is_reference(ref) do
    {:noreply, state}
  end

  @spec traverse_exts(maybe_improper_list(), any()) :: :ok
  defp traverse_exts([], _), do: :ok

  defp traverse_exts([ext | exts], payload) do
    payload = Util.Telegram.remove_command_suffix(payload)

    case process_update(ext, payload) do
      :ok -> traverse_exts(exts, payload)
      :break -> :ok
    end
  end

  # A failing extension must not take the stack down with it: the stack is
  # supervised at the top of :manager, so a crash loop here stops the node.
  # Stopping the traversal keeps Extension.Guard's veto over later
  # extensions intact.
  @spec process_update(atom(), any()) :: :ok | :break
  defp process_update(ext, payload) do
    Extension.process_update(ext, payload)
  catch
    kind, reason ->
      formatted = Exception.format(kind, reason, __STACKTRACE__)
      Logger.error("#{inspect(ext)} failed on an update: #{formatted}")

      Sentry.capture_message("extension failed on an update",
        extra: %{extension: inspect(ext), error: formatted}
      )

      :break
  end
end
