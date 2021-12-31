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
    {_kind, _partition, table, _pid_ets, _} = :ets.lookup_element(@reg_name, -1, 2)

    table
    |> :ets.tab2list()
    |> Enum.map(fn {_id, {pid, _}} -> {pid, Worker.get_state(pid)} end)
  end
end
