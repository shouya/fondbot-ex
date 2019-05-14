defmodule Extension.DevUtil do
  use Extension

  import Util.Telegram

  alias Nadia.Model.{Message, CallbackQuery}

  @impl true
  def on(%Message{text: "/get_chat_id", from: user} = m, _) do
    {:ok, chat_id} = Util.Telegram.chat_id(m)

    msg = """
    chat id: `#{chat_id}`
    user id: `#{user.id}`
    """

    reply(m, msg, parse_mode: "Markdown")
    :ok
  end

  @extensions [
    Extension.Guard,
    Extension.AFK,
    Extension.Weather,
    Extension.Reminder.Manager,
    Extension.Reminder.Builder
  ]

  def on(%Message{text: "/inspect"} = m, _) do
    buttons =
      @extensions
      |> Enum.map(fn mod ->
        name = mod |> Module.split() |> Enum.drop(1) |> Enum.join(".")
        [{:callback, name, "inspect.#{name}"}]
      end)

    kbd = keyboard(:inline, buttons)
    reply(m, "Which extension do you want to inspect?", reply_markup: kbd)
    :ok
  end

  def on(q = %CallbackQuery{data: "inspect." <> mod_name, message: m}, _) do
    answer(q)
    mod = Module.safe_concat("Extension", mod_name)

    if mod not in @extensions do
      edit(m, text: "invalid module")
    else
      state = mod |> :sys.get_state() |> inspect(pretty: true) |> escape(:html)
      status = mod |> :sys.get_status() |> inspect(pretty: true) |> escape(:html)

      msg = """
      State:
      <pre>#{state}</pre>

      Status:
      <pre>#{status}</pre>
      """

      edit(m, text: msg, parse_mode: "HTML")
    end

    :ok
  end
end
