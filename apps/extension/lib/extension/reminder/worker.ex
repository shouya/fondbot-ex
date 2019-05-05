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
    :repeat_time,
    :repeat_ref,
    :killed
  ]

  defstart start_link(param) do
    state =
      __MODULE__
      |> struct!(Map.merge(%{setup_time: Util.Time.now(), repeat_count: 0}, param))

    {kickoff(state, :timer), kickoff(state, :repeat)}
    |> case do
      {{:stop, _}, {:stop, _}} ->
        send(self(), :suicide)
        initial_state(state)

      {_, {:ok, s}} ->
        initial_state(s)

      {{:ok, s}, _} ->
        initial_state(s)
    end
  end

  def kickoff(state, :timer) do
    case next_reminder(state) do
      :stop ->
        {:stop, state}

      {:ok, time} ->
        delay = Timex.diff(time, Util.Time.now(), :milliseconds)
        Process.send_after(self(), :remind, delay)
        {:ok, state}
    end
  end

  def kickoff(state = %{repeat_time: nil}, :repeat) do
    {:stop, state}
  end

  def kickoff(state = %{repeat_time: repeat_time}, :repeat) do
    diff = Timex.diff(repeat_time, DateTime.utc_now(), :seconds)

    if diff > 0 do
      {:ok, repeat(state, diff)}
    else
      {:stop, state}
    end
  end

  defhandleinfo :suicide do
    stop_server(:shutdown)
  end

  defhandleinfo :save do
    send(Extension.Reminder.Manager, :save)
    noreply()
  end

  defhandleinfo :remind, state: state do
    send(self(), :save)

    text = """
    #{message_digest(state.setup_msg)}
    (#{ordinal(state.repeat_count + 1)} alert)

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

    state
    |> repeat(@default_repeat_duration)
    |> Map.merge(%{
      notify_msg: msg,
      repeat_count: state.repeat_count + 1
    })
    |> new_state()
  end

  # triggered when a inline button on specific reminder is clicked
  defcast on_callback("done"), state: state do
    Process.cancel_timer(state.repeat_ref)

    case kickoff(state, :timer) do
      {:stop, _} ->
        edit(state.notify_msg,
          text: "Reminder finished! (on #{ordinal(state.repeat_count)} alert)",
          reply_to_message_id: state.setup_msg.message_id
        )

        stop_server(:shutdown)

      {:ok, state} ->
        send(self(), :save)
        {:ok, time} = next_reminder(state)

        edit(state.notify_msg,
          text: """
          Reminder finished! (on #{ordinal(state.repeat_count)} alert)

          Next reminder at #{Util.Time.format_exact_and_humanize(time)}
          """,
          reply_to_message_id: state.setup_msg.message_id
        )

        state
        |> Map.merge(%{
          repeat_count: 0,
          repeat_ref: nil,
          repeat_time: nil,
          notify_msg: nil
        })
        |> new_state()
    end
  end

  defcast on_callback("delete"), state: state do
    if state.repeat_ref, do: Process.cancel_timer(state.repeat_ref)
    stop_server(:shutdown)
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
    send(self(), :save)
    next_alert = Timex.shift(Util.Time.now(), seconds: duration)

    text = """
    Okay, I'll remind you about #{message_digest(state.setup_msg)} later.

    Next alert: #{Util.Time.format_exact_and_humanize(next_alert)}
    """

    callback = fn icon, action ->
      {:callback, icon, "reminder.worker.#{state.id}.#{action}"}
    end

    edit(state.notify_msg,
      text: text,
      reply_markup:
        keyboard(:inline, [
          [
            callback.("✅", "done"),
            callback.("Del", "delete")
          ]
        ])
    )

    state
    |> repeat(duration)
    |> new_state()
  end

  def repeat(state, sec) do
    send(self(), :save)
    if state.repeat_ref, do: Process.cancel_timer(state.repeat_ref)
    repeat_time = Timex.shift(DateTime.utc_now(), seconds: sec)
    repeat_ref = Process.send_after(self(), :remind, sec * 1000)
    %{state | repeat_time: repeat_time, repeat_ref: repeat_ref}
  end

  defcall get_config(), state: s do
    s |> Map.from_struct() |> reply()
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

    time =
      Timex.set(
        Util.Time.now(),
        hour: time.hour,
        minute: time.minute,
        second: time.second
      )

    if Timex.before?(time, now) do
      {:ok, Timex.shift(time, days: 1)}
    else
      {:ok, time}
    end
  end
end
