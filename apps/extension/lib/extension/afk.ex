defmodule Extension.AFK do
  use Extension

  alias Nadia.Model.Message

  defstruct [
    :afk_at,
    :afk_user,
    :reason,
    :last_notify
  ]

  @impl true
  def on(:message, %Message{text: "/afk", from: user} = m, :noafk) do
    reply_status(m, :set)
    {:ok, set_afk(user)}
  end

  @impl true
  def on(:message, %Message{text: "/afk " <> reason, from: user} = m, :noafk) do
    reply_status(m, :set)
    {:ok, set_afk(user, reason)}
  end

  @impl true
  def on(:message, %Message{text: "/noafk"} = m, %__MODULE__{}) do
    reply_status(m, :unset)
    {:ok, :noafk}
  end

  @impl true
  def on(:message, %Message{} = msg, %__MODULE__{} = s) do
    if should_notify(s) do
      notify_afk(msg, s)
      {:ok, %{s | last_notify: DateTime.utc_now()}}
    else
      :ok
    end
  end

  @impl true
  def new(), do: :noafk

  defp set_afk(user, reason \\ nil) do
    %__MODULE__{
      afk_at: DateTime.utc_now(),
      afk_user: user,
      reason: reason,
      last_notify: nil
    }
  end

  @afk_conf Application.get_env(:extension, :afk, interval: 60)
  defp should_notify(%{last_notify: last_notify}) do
    interval = Keyword.get(@afk_conf, :interval)
    last_notify = last_notify || DateTime.from_unix!(0)
    now = DateTime.utc_now()
    DateTime.diff(now, last_notify) >= interval
  end

  defp notify_afk(
         %Message{message_id: id, chat: %{id: chat_id}},
         %{
           afk_at: afk_at,
           afk_user: afk_user,
           reason: reason
         }
       ) do
    text =
      :erlang.iolist_to_binary([
        Util.Telegram.user_name(afk_user),
        " is afk now.\n",
        "AFK set time: ",
        ["_", Util.Time.format_exact_and_humanize(afk_at), "_"],
        (reason && ["\n*Reason*: ", reason]) || []
      ])

    Nadia.send_message(
      chat_id,
      text,
      reply_to_message_id: id,
      parse_mode: "Markdown"
    )
  end

  defp reply_status(%{message_id: id, chat: %{id: chat_id}}, status) do
    text = "AFK #{status}"
    Nadia.send_message(chat_id, text, reply_to_message_id: id)
  end
end
