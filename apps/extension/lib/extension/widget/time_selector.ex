defmodule Extension.Widget.TimeSelector do
  use ExActor.GenServer

  import Util.Telegram

  defstruct [:msg, :time, :stage]

  defstart start_link(msg) do
    send(self(), :init)

    initial_state(%__MODULE__{
      msg: msg,
      time: Timex.local(),
      stage: :init
    })
  end

  defcast callback("set-hr"), state: %{msg: msg, time: time} = s do
    text = """
    Current time: #{format_time(time)}
    Enter the hour you want to set (0-23 or 1-12am/pm):
    """

    ask(msg, text)

    new_state(%{s | stage: :set_hr})
  end

  defcast callback("set-min"), state: %{msg: msg, time: time} = s do
    text = """
    Current time: #{format_time(time)}
    Enter the minutes you want to set (0-59):
    """

    ask(msg, text)
    new_state(%{s | stage: :set_min})
  end

  defcast callback("reset-min"), state: %{msg: msg, time: time} = s do
    new_time = time |> Timex.set(minute: 0, second: 0)
    prompt({:edit, msg}, new_time)
    new_state(%{s | time: new_time})
  end

  defcast callback("reset-now"), state: %{msg: msg} = s do
    new_time = Timex.local()
    prompt({:edit, msg}, new_time)
    new_state(%{s | time: new_time})
  end

  defcast callback("5min"), state: state do
    advance_and_prompt(state, 30)
  end

  defcast callback("10min"), state: state do
    advance_and_prompt(state, 10 * 60)
  end

  defcast callback("30min"), state: state do
    advance_and_prompt(state, 30 * 60)
  end

  defcast callback("1hr"), state: state do
    advance_and_prompt(state, 60 * 60)
  end

  defcast callback("2hr"), state: state do
    advance_and_prompt(state, 2 * 60 * 60)
  end

  defcast callback("-1hr"), state: state do
    advance_and_prompt(state, -60 * 60)
  end

  defcast callback("custom"), state: %{msg: msg, time: time} = s do
    text = """
    Current time: #{format_time(time)}
    Enter the time you want to set (hh:mm):
    """

    ask(msg, text)
    new_state(%{s | stage: :custom})
  end

  defcast callback("done"), from: from, state: %{msg: msg, time: time} do
    diff = Timex.diff(time, DateTime.utc_now())

    if diff < 5 do
      prompt(
        {:edit, msg},
        time,
        "Invalid time. The time must be at least 5 secs from now.\n\n"
      )

      noreply()
    else
      stop_server({:shutdown, {:time_set, time, msg}})
    end
  end

  defcast callback("cancel"), state: %{msg: msg} do
    stop_server({:shutdown, {:cancel, msg}})
  end

  defcast callback(_) do
    noreply()
  end

  defcast message(text), state: %{stage: :set_hr} = s do
    prompt = "Enter the hour you want to set (0-23 or 1-12am/pm):"
    handle_custom_text(text, prompt, :set_hr, s)
  end

  defcast message(text), state: %{stage: :set_min} = s do
    prompt = "Enter the minutes you want to set (0-59):"
    handle_custom_text(text, prompt, :set_min, s)
  end

  defcast message(text), state: %{stage: :custom} = s do
    prompt = """
    Enter the time you want to set (HH:MM):
    HH: 0-23, MM: 0-59
    """

    handle_custom_text(text, prompt, :custom, s)
  end

  defcast message(_) do
    noreply()
  end

  defhandleinfo :init, state: %{msg: msg, time: time} do
    prompt({:edit, msg}, time)
    noreply()
  end

  defp text_to_time(text, curr_time, :set_hr) do
    case Integer.parse(text) do
      {n, ""} when 0 <= n and n <= 23 ->
        curr_time |> Timex.set(hour: n, second: 0)

      {n, "am"} when 1 <= n and n <= 12 ->
        curr_time |> Timex.set(hour: Integer.mod(n, 12), second: 0)

      {n, " am"} when 1 <= n and n <= 12 ->
        curr_time |> Timex.set(hour: Integer.mod(n, 12), second: 0)

      {n, "pm"} when 1 <= n and n <= 12 ->
        curr_time |> Timex.set(hour: 12 + Integer.mod(n, 12), second: 0)

      {n, " pm"} when 1 <= n and n <= 12 ->
        curr_time |> Timex.set(hour: 12 + Integer.mod(n, 12), second: 0)

      _ ->
        :invalid
    end
  end

  defp text_to_time(text, curr_time, :set_min) do
    case Integer.parse(text) do
      {n, ""} when 0 <= n and n <= 59 ->
        curr_time |> Timex.set(minute: n, second: 0)

      _ ->
        :invalid
    end
  end

  defp text_to_time(text, curr_time, :custom) do
    with {hr, ":" <> min} when 0 <= hr and hr <= 23 <- Integer.parse(text),
         {min, ""} when 0 <= min and min <= 59 <- Integer.parse(min) do
      Timex.set(curr_time, hour: hr, minute: min, second: 0)
    else
      _ -> :invalid
    end
  end

  defp handle_custom_text(text, prompt, mode, %{msg: msg, time: time} = s) do
    new_time = text_to_time(text, time, mode)

    cond do
      text in ["Cancel", "cancel"] ->
        {:ok, new_msg} = prompt({:reset, msg}, time)
        new_state(%{s | stage: :init, msg: new_msg})

      new_time in [:invalid] ->
        header = """
        Failed to parse input, please try again.
        Current time: #{format_time(time)}\n
        """

        {:ok, new_msg} = reset(msg, header <> prompt, reply_markup: force_reply())
        new_state(%{s | msg: new_msg})

      new_time ->
        {:ok, new_msg} = prompt({:reset, msg}, new_time)
        new_state(%{s | stage: :init, msg: new_msg, time: new_time})
    end
  end

  defp format_time(time) do
    Util.Time.format_exact_and_humanize(time)
  end

  defp ask(msg, text) do
    edit(msg, text: text)
  end

  @keyboard_set %{
    reminder: [
      [
        {:callback, "set hr", "reminder.set-time.set-hr"},
        {:callback, "set min", "reminder.set-time.set-min"},
        {:callback, "min->0", "reminder.set-time.reset-min"},
        {:callback, "now", "reminder.set-time.reset-now"}
      ],
      [
        {:callback, "5 min", "reminder.set-time.5min"},
        {:callback, "10 min", "reminder.set-time.10min"},
        {:callback, "30 min", "reminder.set-time.30min"},
        {:callback, "2 hr", "reminder.set-time.1hr"}
      ],
      [
        {:callback, "-1 hr", "reminder.set-time.-1hr"},
        {:callback, "custom", "reminder.set-time.custom"},
        {:callback, "done", "reminder.set-time.done"},
        {:callback, "cancel", "reminder.set-time.cancel"}
      ]
    ]
  }

  defp prompt(action, curr_time, header \\ "")

  defp prompt({:edit, msg}, curr_time, header) do
    text = """
    #{header}Current time: #{format_time(curr_time)}
    Adjust time using the button below.
    """

    edit(msg, text: text, reply_markup: keyboard(:inline, @keyboard_set[:reminder]))
  end

  defp prompt({:reset, msg}, curr_time, header) do
    text = """
    #{header}Current time: #{format_time(curr_time)}
    Adjust time using the button below.
    """

    reset(msg, text, reply_markup: keyboard(:inline, @keyboard_set[:reminder]))
  end

  defp advance_and_prompt(%{msg: msg, time: time} = s, sec) do
    new_time = Timex.shift(time, seconds: sec)
    prompt({:edit, msg}, new_time)
    new_state(%{s | time: new_time})
  end
end
