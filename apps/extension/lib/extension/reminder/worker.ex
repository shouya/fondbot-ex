defmodule Extension.Reminder.Worker do
  use ExActor.GenServer

  import Util.Telegram
  import Util.Number

  @default_repeat_duration 10 * 60 * 1000

  defstruct [
    :id,
    :setup_msg,
    :notify_msg,
    :time,
    :recur_pattern,
    :setup_time,
    :repeat_count,
    :repeat_ref
  ]

  defstart start_link(param) do
    map =
      Map.merge(
        %{
          setup_time: DateTime.utc_now(),
          repeat_count: 1
        },
        param
      )

    send(self(), :kickoff)

    initial_state(struct!(__MODULE__, map))
  end

  defhandleinfo :kickoff, state: s do
    IO.inspect(:kickoff)

    case next_reminder(s) do
      :stop ->
        stop_server(:timeout)

      {:ok, time} ->
        IO.inspect(time)
        delay = Timex.diff(time, Util.Time.now(), :milliseconds)
        Process.send_after(self(), :remind, delay)
        noreply()
    end
  end

  defhandleinfo :remind, state: state do
    text = """
    (#{ordinal(state.repeat_count)} alert)

    Reminder set at #{Util.Time.format_exact_and_humanize(state.setup_time)}
    _Please press "✅", or I'll remind again every 10 minutes._
    """

    callback = fn icon, action ->
      {:callback, icon, "reminder.worker.#{state.id}.#{action}"}
    end

    {:ok, msg} =
      Util.Telegram.reply(state.setup_msg, text,
        parse_mode: "Markdown",
        reply_markup:
          keyboard(:inline, [
            [
              callback.("✅", "done"),
              callback.("Del", "delete")
            ],
            [
              callback.("💤5 min", "snooze-5"),
              callback.("💤30 min", "snooze-30"),
              callback.("💤1 hr", "snooze-60")
            ]
          ])
      )

    if state.notify_msg, do: delete_message(state.notify_msg)
    if state.repeat_ref, do: Process.cancel_timer(state.repeat_ref)
    repeat_ref = Process.send_after(self(), :remind, @default_repeat_duration)

    new_state(%{
      state
      | notify_msg: msg,
        repeat_count: state.repeat_count + 1,
        repeat_ref: repeat_ref
    })
  end

  # triggered when a inline button on specific reminder is clicked
  defcast on_callback("done"), state: state do
    IO.inspect({:btn_hit, :done})
    Process.cancel_timer(state.repeat_ref)

    case next_reminder(state) do
      :stop ->
        edit(state.notify_msg,
          text: "Reminder finished! (on #{ordinal(state.repeat_count)} alert)",
          reply_to_message_id: state.setup_msg.message_id
        )

        stop_server(:normal)

      {:ok, time} ->
        edit(state.notify_msg,
          text: """
          Reminder finished! (on #{ordinal(state.repeat_count)} alert)

          Next reminder at #{Util.Time.format_exact_and_humanize(time)}
          """,
          reply_to_message_id: state.setup_msg.message_id,
          reply_markup: nil
        )

        send(self(), :kickoff)
        new_state(%{state | repeat_count: 1, repeat_ref: nil, notify_msg: nil})
    end
  end

  defcast on_callback("delete"), state: state do
    IO.inspect({:btn_hit, :del})
    if state.repeat_ref, do: Process.cancel_timer(state.repeat_ref)
    stop_server(:delete)
  end

  defcast on_callback("snooze-5"), state: state do
    snooze(state, 5 * 60)
  end

  defcast on_callback("snooze-30"), state: state do
    snooze(state, 30 * 60)
  end

  defcast on_callback("snooze-60"), state: state do
    snooze(state, 60 * 60)
  end

  def snooze(state, duration) do
    next_alert = Timex.add(Util.Time.now(), second: duration)

    text = """
    Okay, I'll remind you again later.

    Next alert: #{Util.Time.format_exact_and_humanize(next_alert)}
    """

    edit(state.notify_msg, text: text, reply_markup: nil)

    if state.repeat_ref, do: Process.cancel_timer(state.repeat_ref)
    repeat_ref = Process.send_after(self(), :remind, duration)

    new_state(%{state | repeat_ref: repeat_ref})
  end

  defcall get_config(), state: s do
    s |> Map.from_struct() |> Map.put(:pid, self()) |> reply()
  end

  def next_reminder(%{time: time, recur_pattern: :oneshot}) do
    if Timex.before?(time, DateTime.utc_now()) do
      :stop
    else
      {:ok, time}
    end
  end

  def next_reminder(%{time: time, recur_pattern: :daily}) do
    now = DateTime.utc_now()

    DateTime.utc_now()
    |> Util.Time.to_local()
    |> Timex.set(
      hour: time.hour,
      minute: time.minute,
      second: time.second
    )
    |> case do
      time when time <= now -> {:ok, Timex.add(time, day: 1)}
      time -> {:ok, time}
    end
  end
end
