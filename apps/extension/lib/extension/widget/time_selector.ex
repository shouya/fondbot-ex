defmodule Extension.Widget.TimeSelector do
  defmodule NaturalTimeParser do
    import NimbleParsec

    ws = string(" ") |> repeat() |> ignore()
    int2 = integer(min: 1, max: 2)

    ampm = choice([string("am"), string("pm")])

    rel_day =
      choice([
        string("today"),
        string("tomorrow"),
        replace(string("tmr"), "tomorrow")
      ])

    weekday =
      choice([
        string("monday"),
        string("tuesday"),
        string("wednesday"),
        string("thursday"),
        string("friday"),
        string("saturday"),
        string("sunday"),
        replace(string("mon"), "monday"),
        replace(string("tue"), "tuesday"),
        replace(string("wed"), "wednesday"),
        replace(string("thu"), "thursday"),
        replace(string("fri"), "friday"),
        replace(string("sat"), "saturday"),
        replace(string("sun"), "sunday")
      ])

    rel_adv = choice([string("this"), string("next")])

    time =
      choice([
        int2
        |> concat(ignore(string(":")))
        |> concat(int2)
        |> concat(ws)
        |> concat(ampm)
        |> tag(:hm_ap),
        int2 |> concat(ws) |> concat(ampm) |> tag(:h_ap),
        int2 |> concat(ignore(string(":"))) |> concat(int2) |> tag(:hm)
      ])

    day =
      choice([
        rel_day |> tag(:rel_day),
        rel_adv |> concat(ws) |> concat(weekday) |> tag(:rel_weekday),
        weekday |> tag(:weekday)
      ])

    defparsec(
      :datetime,
      choice([
        day |> concat(ws) |> concat(time) |> tag(:day_time),
        time |> concat(ws) |> concat(day) |> tag(:time_day),
        time |> tag(:time_only)
      ])
    )

    def parse(str, rel \\ Util.Time.now()) do
      case datetime(str) do
        {:ok, result, _, _, _, _} ->
          parse_datetime(rel, result)

        _ ->
          nil
      end
    end

    defp parse_datetime(now, day_time: [day, time]) do
      date = parse_day(now, [day])
      time = parse_time(now, [time])
      Timex.set(now, date: date, time: time)
    end

    defp parse_datetime(now, time_day: [time, day]) do
      date = parse_day(now, [day])
      time = parse_time(now, [time])
      Timex.set(now, date: date, time: time)
    end

    defp parse_datetime(now, time_only: [time]) do
      time = parse_time(now, [time])
      Timex.set(now, time: time)
    end

    defp parse_day(now, rel_day: ["today"]) do
      Timex.to_date(now)
    end

    defp parse_day(now, rel_day: ["tomorrow"]) do
      now |> Timex.to_date() |> Timex.shift(days: 1)
    end

    defp parse_day(now, weekday: [weekday]) do
      parse_day(now, rel_weekday: ["", weekday])
    end

    defp parse_day(now, rel_weekday: [adv, weekday]) do
      curr_day = Timex.weekday(now)
      target_day = Timex.day_to_num(weekday)

      offset =
        case adv do
          "" -> rem(target_day - curr_day + 7, 7)
          "this" -> target_day - curr_day
          "next" -> target_day + 7 - curr_day
        end

      now
      |> Timex.to_date()
      |> Timex.shift(days: offset)
    end

    defp parse_time(now, h_ap: [h, ap]) do
      parse_time(now, hm_ap: [h, 0, ap])
    end

    defp parse_time(now, hm_ap: [h, m, "am"]) do
      now
      |> Timex.set(hour: rem(h, 12), minute: m, second: 0)
      |> to_time()
    end

    defp parse_time(now, hm_ap: [h, m, "pm"]) do
      now
      |> Timex.set(hour: rem(h, 12) + 12, minute: m, second: 0)
      |> to_time()
    end

    defp parse_time(now, hm: [h, m]) do
      now
      |> Timex.set(hour: h, minute: m, second: 0)
      |> to_time()
    end

    defp to_time(datetime) do
      {datetime.hour, datetime.minute, datetime.second}
    end
  end

  use ExActor.GenServer

  import Util.Telegram

  defstruct [:msg, :time, :stage]

  defstart start_link(msg) do
    send(self(), :init)

    initial_state(%__MODULE__{
      msg: msg,
      time: Util.Time.now(),
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
    new_time = Util.Time.now()
    prompt({:edit, msg}, new_time)
    new_state(%{s | time: new_time})
  end

  defcast callback("20sec"), state: state do
    advance_and_prompt(state, 20)
  end

  defcast callback("1min"), state: state do
    advance_and_prompt(state, 60)
  end

  defcast callback("10min"), state: state do
    advance_and_prompt(state, 10 * 60)
  end

  defcast callback("1hr"), state: state do
    advance_and_prompt(state, 60 * 60)
  end

  defcast callback("24hr"), state: state do
    advance_and_prompt(state, 24 * 60 * 60)
  end

  defcast callback("-1hr"), state: state do
    advance_and_prompt(state, -60 * 60)
  end

  defcast callback("input"), state: %{msg: msg, time: time} = s do
    text = """
    Current time: #{format_time(time)}
    Enter the time you want to set (free form):
    e.g. 11:20, tmr 8am, next tue 10pm
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
    Enter the time you want to set (free form):
    e.g. 11:20, tmr 8am, next tue 10pm
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

  defhandleinfo(_any, do: noreply())

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

  defp text_to_time(text, _curr_time, :custom) do
    IO.inspect({text, NaturalTimeParser.parse(text)})

    case NaturalTimeParser.parse(text) do
      nil -> :invalid
      t -> t
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
        {:callback, "min->0", "reminder.set-time.reset-min"},
        {:callback, "now", "reminder.set-time.reset-now"}
      ],
      [
        {:callback, "1 min", "reminder.set-time.1min"},
        {:callback, "10 min", "reminder.set-time.10min"},
        {:callback, "1 hr", "reminder.set-time.1hr"},
        {:callback, "24 hr", "reminder.set-time.24hr"}
      ],
      [
        {:callback, "-1 hr", "reminder.set-time.-1hr"},
        {:callback, "input", "reminder.set-time.input"},
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
