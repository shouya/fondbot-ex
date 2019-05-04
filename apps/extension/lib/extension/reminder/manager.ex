defmodule Extension.Reminder.Manager do
  use Extension

  alias Extension.Reminder.Worker

  alias Nadia.Model.CallbackQuery

  # workers: map(ref_id -> map(pid, ...))
  defstruct [:workers]

  def before_init() do
    Process.flag(:trap_exit, true)
  end

  def new() do
    %__MODULE__{workers: %{}}
  end

  def from_saved(conf) do
    workers =
      conf.workers
      |> Enum.map(fn worker ->
        {:ok, pid} = Worker.start_link(worker)
        worker |> Map.put(:pid, pid)
      end)

    new() |> Map.put(:workers, workers)
  end

  def spawn_worker(%{} = params) do
    GenServer.call(__MODULE__, {:spawn_worker, params})
  end

  def handle_call({:spawn_worker, payload}, _, state) do
    id = Nanoid.generate()
    param = Map.put(payload, :id, id)

    case Worker.start_link(param) do
      {:ok, pid} ->
        new_state = put_in(state.workers[id], %{pid: pid})
        send(self(), {:update_worker_config, id})

        {:reply, :ok, new_state}

      {:error, e} ->
        {:reply, {:error, e}, state}
    end
  end

  # reminder.worker.<ref_id>.<command>
  def on(%CallbackQuery{data: "reminder.worker." <> id_and_cmd}, s) do
    IO.inspect({:got_btn, id_and_cmd})

    with [id, command] <- id_and_cmd |> String.split("."),
         pid <- s.workers[id].pid do
      Worker.on_callback(pid, command)
      send(self(), {:update_worker_config, id})
      {:ok, s}
    else
      _ -> :ok
    end
  end

  def on_info({:update_worker_config, id}, s) do
    pid = s.workers[id].pid
    conf = Worker.get_config(pid)
    new_s = put_in(s.workers[id], conf)

    {:noreply, new_s}
  end

  def on_info({:EXIT, from, _reason}, state) do
    dead_children = for {id, %{pid: ^from}} <- state.workers, do: id
    new_state = update_in(state.workers, &Map.drop(&1, dead_children))
    {:noreply, new_state}
  end

  def on_info({:EXIT, from, _reason}, state) do
  end

  def on_info({:stop, ref_id}, s) do
    s
    |> Map.update!(:workers, &Map.delete(&1, ref_id))
    |> (&{:noreply, &1}).()
  end
end
