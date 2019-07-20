defmodule Extension.Reminder.Supervisor do
  use Supervisor

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [
      {Registry, keys: :unique, name: :reminders},
      {DynamicSupervisor,
       [
         strategy: :one_for_one,
         name: Extension.Reminder.WorkerSupervisor
       ]},
      Extension.Reminder.Manager,
      Extension.Reminder.Builder
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
