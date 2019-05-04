defmodule Extension.Reminder.Manager do
  use Extension

  import Util.Telegram

  alias Extension.Reminder.Worker
  alias Nadia.Model.CallbackQuery

  def before_init() do
    Process.flag(:trap_exit, true)
  end

  def new() do
    %{}
  end

  def from_saved(workers) do
    workers
    |> Enum.flat_map(fn %{id: id} = conf ->
      case Worker.start_link(conf) do
        {:ok, pid} -> [{id, pid}]
        _ -> []
      end
    end)
    |> Enum.into(%{})
  end

  def save(workers) do
    config =
      workers
      |> Task.async_stream(fn {_, pid} ->
        if Process.alive?(pid) do
          Worker.get_config(pid)
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.to_list()

    Extension.Store.save_state(__MODULE__, config)
  end

  def spawn_worker(%{} = params) do
    GenServer.call(__MODULE__, {:spawn_worker, params})
  end

  def handle_call({:spawn_worker, payload}, _, workers) do
    id = Nanoid.generate()
    param = Map.put(payload, :id, id)

    case Worker.start_link(param) do
      {:ok, pid} ->
        IO.inspect({:w, workers})
        new_workers = Map.put(workers, id, pid)
        IO.inspect({:nw, new_workers})
        {:reply, :ok, new_workers}

      {:error, e} ->
        {:reply, {:error, e}, workers}
    end
  end

  # reminder.worker.<ref_id>.<command>
  def on(%CallbackQuery{data: "reminder.worker." <> id_and_cmd} = q, s) do
    answer(q)

    with [id, command] <- id_and_cmd |> String.split("."),
         pid <- s[id] do
      Worker.on_callback(pid, command)
      {:ok, s}
    else
      _ -> :ok
    end
  end

  def on_info({:EXIT, from, _reason}, workers) do
    dead_children = for {id, ^from} <- workers, do: id
    IO.inspect(dead_children)
    new_workers = Map.drop(workers, dead_children)
    IO.inspect(new_workers)
    {:noreply, new_workers}
  end
end
