defmodule Extension.Reminder.Controller do
  require Logger

  alias Extension.Reminder.{Worker, WorkerSupervisor}

  @reg_name :reminders

  def start_worker(id, param) do
    spec = %{id: id, start: {Worker, :start_link, [param]}}
    DynamicSupervisor.start_child(WorkerSupervisor, spec)
  end

  def terminate_worker(id) do
    case lookup_worker(id) do
      nil ->
        {:error, {:worker_not_exist, id}}

      {pid, _conf} ->
        Logger.warn("Someone asked me to terminate worker: #{id}")
        DynamicSupervisor.terminate_child(WorkerSupervisor, pid)
    end
  end

  def save_worker_state(id, state) do
    Registry.update_value(@reg_name, id, fn _ -> state end)
  end

  def lookup_worker(id) do
    case Registry.lookup(@reg_name, id) do
      [] -> nil
      [{pid, conf}] -> {pid, conf}
    end
  end

  @spec all_workers() :: [{pid(), term()}]
  def all_workers() do
    {_kind, _partition, table, _pid_ets, _} = :ets.lookup_element(@reg_name, -1, 2)

    table
    |> :ets.tab2list()
    |> Enum.map(fn {_id, {pid, conf}} -> {pid, conf} end)
  end
end
