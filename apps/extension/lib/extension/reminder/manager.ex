defmodule Extension.Reminder.Manager do
  use Extension

  import Util.Telegram

  alias Extension.Reminder.{Controller, Worker}
  alias Nadia.Model.{Message, CallbackQuery}

  def new() do
    nil
  end

  def from_saved(workers) do
    for %{id: id} = conf <- workers do
      Controller.start_worker(id, conf)
    end

    save()
    nil
  end

  def save(), do: save(nil)

  def save(_) do
    config = get_workers_config()
    Extension.Store.save_state(__MODULE__, config)
  end

  @doc "callback when workers changed state to save current states"
  def worker_state_changed(id \\ :all) do
    send(__MODULE__, {:worker_state_changed, id})
  end

  def spawn_worker(%{} = params) do
    id = Nanoid.generate()
    params = Map.put(params, :id, id)
    {:ok, _pid} = Controller.start_worker(id, params)
    save()
  end

  def on(%CallbackQuery{data: "reminder.manager.cancel"} = q, _) do
    answer(q)
    edit(q.message, text: "Nevermind.")
    :ok
  end

  def on(%CallbackQuery{data: "reminder.manager.delete." <> id} = q, _) do
    answer(q)

    case Controller.terminate_worker(id) do
      :ok ->
        edit(q.message, text: "Reminder deleted.")

      {:error, _} ->
        edit(q.message, text: "Reminder not found.")
    end

    :ok
  end

  def on(%CallbackQuery{data: "reminder.manager.skip." <> id} = q, _) do
    answer(q)

    case Controller.lookup_worker(id) do
      nil ->
        edit(q.message, text: "Reminder not found.")

      pid ->
        edit(q.message, text: "Skipping next reminder.")
        Worker.skip_next(pid)
        edit(q.message, text: "Done.")
    end

    :ok
  end

  def on(%CallbackQuery{data: "reminder.manager.ack"} = q, _) do
    edit(q.message, text: "Ok.")
    :ok
  end

  def on(%CallbackQuery{data: "reminder.manager.detail." <> id} = q, _) do
    answer(q)

    case Controller.lookup_worker(id) do
      pid when is_pid(pid) ->
        conf = Worker.get_state(pid)
        conf = Map.drop(conf, [:notify_msg, :setup_msg])

        keyboard =
          keyboard(:inline, [
            [
              {:callback, "Skip", "reminder.manager.skip." <> id},
              {:callback, "Del", "reminder.manager.delete." <> id},
              {:callback, "OK", "reminder.manager.ack"}
            ]
          ])

        edit(q.message,
          text: "```\n#{inspect(conf, pretty: true)}\n```",
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
  def on(%CallbackQuery{data: "reminder.worker." <> id_and_cmd} = q, _) do
    answer(q)

    with [id, command] <- String.split(id_and_cmd, "."),
         pid when is_pid(pid) <- Controller.lookup_worker(id) do
      Worker.on_callback(pid, command)
      :ok
    else
      _ -> :ok
    end
  end

  def on(%Message{text: "/list_reminders"} = m, _) do
    import Util.Time

    confs = get_workers_config()

    confs
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
        reply(m, "Choose reminder to inspect", reply_markup: keyboard(:inline, buttons))
    end

    :ok
  end

  def on_info({:worker_state_changed, :all}, s) do
    save()
    {:noreply, s}
  end

  def on_info({:worker_state_changed, _id}, s) do
    save()
    {:noreply, s}
  end

  def get_workers_config() do
    Enum.map(Controller.all_workers(), fn {_pid, conf} -> conf end)
  end
end
