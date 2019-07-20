defmodule Extension.Reminder.Controller do
  alias Extension.Reminder.{Worker, WorkerSupervisor}

  def start_worker(id, param) do
    spec = %{id: id, start: {Worker, :start_link, [param]}}
    DynamicSupervisor.start_child(WorkerSupervisor, spec)
  end

  def terminate_worker(id) do
    case Registry.lookup(:reminders, id) do
      [] ->
        {:error, {:worker_not_exist, id}}

      [{pid, _}] ->
        DynamicSupervisor.terminate_child(WorkerSupervisor, pid)
    end
  end

  def save_worker_state(id, state) do
    Registry.update_value(__MODULE__, id, fn _ -> state end)
  end

  def all_workers() do
    {_kind, _partition, table, _pid_ets, _} = :ets.lookup_element(:reminders, -1, 2)

    :ets.tab2list(table)
  end
end
