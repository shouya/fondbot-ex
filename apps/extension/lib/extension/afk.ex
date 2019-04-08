defmodule Extension.AFK do
  use GenServer

  alias Nadia.Model.Message

  defstruct [
    :afk_at,
    :afk_user,
    :reason,
    :last_notify
  ]

  def start_link do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_) do
    {:ok, nil}
  end

  defp new(user, reason \\ nil) do
    %__MODULE__{
      afk_at: DateTime.utc_now(),
      afk_user: user,
      reason: reason,
      last_notify: nil
    }
  end

  def handle_call({:on_message, %Message{text: "/afk", from: user}}, _, nil) do
    {:reply, :ok, new(user)}
  end

  def handle_call(
        {
          :on_message,
          %Message{text: "/afk " <> reason, from: user}
        },
        _,
        nil
      ) do
    {:reply, :ok, new(user, reason)}
  end

  def handle_call({:on_message, %Message{text: "/noafk"}}, _, %__MODULE__{}) do
    {:reply, :ok, nil}
  end

  def handle_call({:on_message, %Message{} = msg}, _, %__MODULE__{} = s) do
    if should_notify(s) do
      notify_afk(msg, s)
      {:reply, :ok, %{s | last_notify: DateTime.utc_now()}}
    else
      {:reply, :ok, s}
    end
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

    Nadia.send_message(chat_id, text, reply_to_message_id: id)
  end
end
