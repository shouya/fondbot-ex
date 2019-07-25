defmodule Extension.Reminder.Worker do
  require Logger
  use GenServer

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

  @impl GenServer
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
        Logger.info("kickoff timer and repeat both failed, stopping: #{inspect(state)}")
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
      Logger.info("Kickoff failed (diff <= 0): #{inspect(state)}")
      {:stop, state}
    end
  end

  @impl GenServer
  def handle_info(:remind, state) do
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

    new_state =
      state
      |> repeat(@default_repeat_duration)
      |> Map.merge(%{
        notify_msg: msg,
        repeat_count: state.repeat_count + 1
      })

    {:noreply, new_state}
  end

  def save_worker_state(worker) do
    GenServer.call(worker, :save_worker_state)
  end

  @impl GenServer
  def handle_call(:save_worker_state, _from, %{id: id} = state) do
    Extension.Reminder.Controller.save_worker_state(id, state)
    {:reply, :ok, state}
  end

  def on_callback(worker, message) do
    GenServer.cast(worker, {:on_callback, message})
  end

  @doc "triggered when a inline button on specific reminder is clicked"
  @impl GenServer
  def handle_cast({:on_callback, "done"}, state) do
    Process.cancel_timer(state.repeat_ref)

    case kickoff(state, :timer) do
      {:stop, _} ->
        edit(state.notify_msg,
          text: "Reminder finished. (on #{ordinal(state.repeat_count)} alert)",
          reply_to_message_id: state.setup_msg.message_id
        )

        {:stop, :normal, state}

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

        new_state = %{
          state
          | repeat_count: 0,
            repeat_ref: nil,
            repeat_time: nil,
            notify_msg: nil
        }

        {:noreply, new_state}
    end
  end

  def handle_cast({:on_callback, "close"}, state) do
    if state.repeat_ref, do: Process.cancel_timer(state.repeat_ref)

    edit(state.notify_msg,
      text: "Reminder closed. (on #{ordinal(state.repeat_count)} alert)",
      reply_to_message_id: state.setup_msg.message_id
    )

    {:stop, :normal, state}
  end

  def handle_cast({:on_callback, "snooze-5"}, state) do
    snooze(state, 5 * 60)
  end

  def handle_cast({:on_callback, "snooze-30"}, state) do
    snooze(state, 30 * 60)
  end

  def handle_cast({:on_callback, "snooze-60"}, state) do
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

    new_state = repeat(state, duration)
    {:noreply, new_state}
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
