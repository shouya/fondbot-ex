defmodule Extension.Reminder.Builder do
  use Extension

  import Util.Telegram
  alias Nadia.Model.{Message, CallbackQuery}
  alias Extension.Widget.TimeSelector
  alias Extension.Reminder.Manager

  defstruct [:reminders, :stage, :widget, :pending]

  def new() do
    %__MODULE__{}
  end

  def before_init() do
    Process.flag(:trap_exit, true)
  end

  def on(%Message{text: "/remind_me"} = msg, %{widget: w} = s) do
    unless is_nil(w), do: Process.exit(w, :kill)

    reply(
      msg,
      "What do you want to be reminded for?",
      reply_markup: reply_markup(:force_reply)
    )

    pending = %{setup_msg: nil, recur_pattern: nil}
    {:ok, %{s | stage: :remind_msg, widget: nil, pending: pending}}
  end

  def on(%Message{} = msg, %{stage: :remind_msg, pending: pending} = s) do
    kbd = [
      [
        {:callback, "Only once", "reminder.recur.oneshot"},
        {:callback, "Every day", "reminder.recur.daily"}
      ],
      [{:callback, "Cancel", "reminder.recur.cancel"}]
    ]

    reply(
      msg,
      "Got it. Now tell me if you want to be reminded once or every day?",
      reply_markup: keyboard(:inline, kbd)
    )

    {:ok, %{s | stage: :recur, pending: %{pending | setup_msg: msg}}}
  end

  def on(
        %CallbackQuery{data: "reminder.recur." <> pat, message: msg} = q,
        %{stage: :recur, pending: pending} = s
      )
      when pat in ~w[daily oneshot] do
    answer(q)
    {:ok, pid} = TimeSelector.start_link(msg)
    pending = %{pending | recur_pattern: String.to_atom(pat)}
    {:ok, %{s | stage: :set_time, widget: pid, pending: pending}}
  end

  def on(%CallbackQuery{data: "reminder.recur.cancel", message: msg} = q, %{stage: :recur} = s) do
    answer(q)
    cancel(msg, s, :edit)
  end

  def on(
        %CallbackQuery{data: "reminder.set-time." <> cmd} = q,
        %{stage: :set_time, widget: pid}
      ) do
    answer(q)
    TimeSelector.callback(pid, cmd)
    :ok
  end

  def on(%Message{text: text}, %{stage: :set_time, widget: pid}) do
    TimeSelector.message(pid, text)
    :ok
  end

  def on_info({:EXIT, w, {:shutdown, {:time_set, time, msg}}}, s = %{widget: w2}) when w == w2 do
    alias Util.Time
    pending = Map.put(s.pending, :time, time)
    Manager.spawn_worker(pending)

    reminder_repr = message_digest(pending.setup_msg)
    time_repr = "#{Time.humanize(time)} (#{Time.format_exact(time)})"

    text = """
    Reminder set! I'll remind you about #{reminder_repr} #{time_repr}.
    """

    edit(msg, text: text)

    {:noreply, %{s | stage: nil, widget: nil, pending: nil}}
  end

  def on_info({:EXIT, w, {:shutdown, {:cancel, msg}}}, %{stage: :set_time, widget: w2} = s)
      when w == w2 do
    {:ok, new_s} = cancel(msg, s, :edit)
    {:noreply, new_s}
  end

  def cancel(msg, %{widget: w}, :edit) do
    unless is_nil(w), do: Process.exit(w, :kill)
    edit(msg, text: "Reminder not set.")
    {:ok, new()}
  end
end
