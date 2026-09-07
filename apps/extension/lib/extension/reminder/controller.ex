defmodule Extension.Reminder.Controller do
  require Logger

  alias Extension.Reminder.{Worker, WorkerSupervisor}

  @type id_t :: binary()

  @reg_name :reminders

  def start_worker(id, param) do
    spec = %{
      id: id,
      start: {Worker, :start_link, [param]},
      restart: :transient,
      type: :worker
    }

    DynamicSupervisor.start_child(WorkerSupervisor, spec)
  end

  def terminate_worker(id) do
    case lookup_worker(id) do
      nil ->
        {:error, {:worker_not_exist, id}}

      pid ->
        DynamicSupervisor.terminate_child(WorkerSupervisor, pid)
    end
  end

  @spec lookup_worker(id_t()) :: nil | pid()
  def lookup_worker(id) do
    case Registry.lookup(@reg_name, id) do
      [] -> nil
      [{pid, _}] -> pid
    end
  end

  @spec all_workers() :: [{pid(), term()}]
  def all_workers() do
    @reg_name
    |> Registry.select([{{:_, :"$1", :_}, [], [:"$1"]}])
    |> Enum.flat_map(fn pid ->
      case worker_state(pid) do
        {:ok, state} -> [{pid, state}]
        :error -> []
      end
    end)
  end

  # One worker that cannot answer must not stop the others being listed or
  # saved.
  defp worker_state(pid) do
    {:ok, Worker.get_state(pid)}
  catch
    :exit, reason ->
      Logger.warning("Reminder worker #{inspect(pid)} gave no state: #{inspect(reason)}")
      :error
  end
end
