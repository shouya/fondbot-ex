defmodule Extension.Reminder.Worker do
  use ExActor.GenServer

  import Util.Telegram
  import Util.Number, only: [ordinal: 1]

  @default_repeat_duration 10 * 60

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

  def start_link(%{id: id} = param) do
    GenServer.start_link(
      __MODULE__,
      param,
      name: {:via, Registry, {:reminders, id}}
    )
  end

  def init(param) do
    default_param = %{setup_time: Util.Time.now(), repeat_count: 0}

    state =
      param
      |> case do
        %__MODULE__{} -> Map.from_struct(param)
        _ -> param
      end
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
      |> Map.merge(default_param, fn _k, v1, _v2 -> v1 end)

    state = struct!(__MODULE__, state)

    {kickoff(state, :timer), kickoff(state, :repeat)}
    |> case do
      {{:stop, _}, {:stop, _}} ->
        {:stop, :normal}

      {_, {:ok, s}} ->
        {:ok, s}

      {{:ok, s}, _} ->
        {:ok, s}
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
    stop_server(:normal)
  end

  defhandleinfo :remind, state: state do
    Extension.Reminder.Manager.worker_state_changed(state.id)

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
              callback.("❌", "close")
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

  defcall :save_worker_state, state: %{id: id} = state do
    Extension.Reminder.Controller.save_worker_state(id, state)
    reply(:ok)
  end

  # triggered when a inline button on specific reminder is clicked
  defcast on_callback("done"), state: state do
    Process.cancel_timer(state.repeat_ref)

    case kickoff(state, :timer) do
      {:stop, _} ->
        edit(state.notify_msg,
          text: "Reminder finished. (on #{ordinal(state.repeat_count)} alert)",
          reply_to_message_id: state.setup_msg.message_id
        )

        stop_server(:normal)

      {:ok, state} ->
        Extension.Reminder.Manager.worker_state_changed(state.id)
        {:ok, time} = next_reminder(state)

        edit(state.notify_msg,
          text: """
          Reminder finished. (on #{ordinal(state.repeat_count)} alert)

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

  defcast on_callback("close"), state: state do
    if state.repeat_ref, do: Process.cancel_timer(state.repeat_ref)

    edit(state.notify_msg,
      text: "Reminder closed. (on #{ordinal(state.repeat_count)} alert)",
      reply_to_message_id: state.setup_msg.message_id
    )

    stop_server(:normal)
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
    Extension.Reminder.Manager.worker_state_changed(state.id)
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
            callback.("❌", "close")
          ]
        ])
    )

    state
    |> repeat(duration)
    |> new_state()
  end

  def repeat(state, sec) do
    Extension.Reminder.Manager.worker_state_changed(state.id)
    if state.repeat_ref, do: Process.cancel_timer(state.repeat_ref)
    repeat_time = Timex.shift(DateTime.utc_now(), seconds: sec)
    repeat_ref = Process.send_after(self(), :remind, sec * 1000)
    %{state | repeat_time: repeat_time, repeat_ref: repeat_ref}
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
