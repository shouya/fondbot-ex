defmodule Extension.Reminder.Manager do
  use Extension

  import Util.Telegram

  alias Extension.Reminder.Worker
  alias Nadia.Model.{Message, CallbackQuery}

  def before_init() do
    Process.flag(:trap_exit, true)
  end

  def new() do
    %{}
  end

  def from_save(workers) do
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
    config = get_workers_config(workers)
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
        send(self(), :save)
        new_workers = Map.put(workers, id, pid)
        {:reply, :ok, new_workers}

      {:error, e} ->
        {:reply, {:error, e}, workers}
    end
  end

  def on(%CallbackQuery{data: "reminder.manager.cancel"} = q, _) do
    answer(q)
    edit(q.message, text: "Nevermind.")
    :ok
  end

  def on(%CallbackQuery{data: "reminder.manager.delete." <> id} = q, s) do
    answer(q)

    case Map.fetch(s, id) do
      {:ok, pid} ->
        Process.exit(pid, :normal)
        new_s = Map.delete(s, id)
        edit(q.message, text: "Reminder deleted.")
        {:ok, new_s}

      _ ->
        edit(q.message, text: "Reminder not found.")
        :ok
    end
  end

  def on(%CallbackQuery{data: "reminder.manager.ack"} = q, _) do
    edit(q.message, text: "Ok.")
    :ok
  end

  def on(%CallbackQuery{data: "reminder.manager.detail." <> id} = q, s) do
    answer(q)

    case Map.fetch(s, id) do
      {:ok, pid} ->
        conf =
          Worker.get_config(pid)
          |> Map.drop([:notify_msg, :setup_msg])
          |> inspect(pretty: true)

        keyboard =
          keyboard(:inline, [
            [
              {:callback, "Del", "reminder.manager.delete." <> id},
              {:callback, "OK", "reminder.manager.ack"}
            ]
          ])

        edit(q.message,
          text: "```\n#{conf}\n```",
          parse_mode: "Markdown",
          reply_markup: keyboard
        )

        :ok

      _ ->
        edit(q.message, text: "Reminder not found.")
        :ok
    end
  end

  # reminder.worker.<ref_id>.<command>
  def on(%CallbackQuery{data: "reminder.worker." <> id_and_cmd} = q, s) do
    answer(q)

    with [id, command] <- id_and_cmd |> String.split("."),
         {:ok, pid} <- Map.fetch(s, id) do
      Worker.on_callback(pid, command)
      {:ok, s}
    else
      _ -> :ok
    end
  end

  def on(%Message{text: "/list_reminders"} = m, workers) do
    import Util.Time

    workers
    |> get_workers_config()
    |> Enum.sort_by(fn %{setup_time: t} -> t end)
    |> Enum.map(fn c = %{id: id, setup_time: st, time: t, recur_pattern: rp} ->
      digest = message_digest(c.setup_msg)
      text = "#{format_short_date(st)} #{format_short_time(t)}, #{rp} - #{digest}"

      [
        {:callback, text, "reminder.manager.detail." <> id}
      ]
    end)
    |> case do
      [] ->
        reply(m, "No active reminders available")

      buttons ->
        buttons = [[{:callback, "Cancel", "reminder.manager.cancel"}]] ++ buttons
        reply(m, "Choose reminder to delete", reply_markup: keyboard(:inline, buttons))
    end

    :ok
  end

  def on_info({:EXIT, from, _reason}, workers) do
    send(self(), :save)

    dead_children = for {id, ^from} <- workers, do: id
    new_workers = Map.drop(workers, dead_children)
    {:noreply, new_workers}
  end

  def get_workers_config(workers) do
    workers
    |> Task.async_stream(fn {_, pid} ->
      if Process.alive?(pid), do: Worker.get_config(pid)
    end)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, v} -> v end)
  end
end
