defmodule Extension.Guard do
  use Extension

  alias Nadia.Model.{CallbackQuery, InlineQuery, User}

  defstruct [:safe_users, :report_channel]

  @impl true
  def new() do
    case Confex.fetch_env(:extension, :guard) do
      {:ok, conf} ->
        %__MODULE__{
          safe_users: Keyword.fetch!(conf, :safe_users),
          report_channel: Keyword.fetch!(conf, :report_channel)
        }

      :error ->
        :no_guard
    end
  end

  @impl true
  def on(_payload, :no_guard) do
    :ok
  end

  # can't check on inline
  @impl true
  def on(%InlineQuery{}, _) do
    :ok
  end

  @impl true
  def on(payload, guard) do
    case {Util.Telegram.from_user(payload), Util.Telegram.chat_id(payload)} do
      {{:error, _}, _} ->
        # probably shouldn't
        :ok

      {_, {:error, _}} ->
        # probably shouldn't
        :ok

      {{:ok, %User{id: user_id} = user}, {:ok, chat_id}} ->
        if authorized?(user_id, chat_id, guard) do
          handle_guard_command(payload, guard)
        else
          report_error(payload, user, guard)
          send_warning(chat_id)
          :break
        end
    end
  end

  defp report_error(payload, %{id: user_id} = user, %{report_channel: channel_id}) do
    user_name = Util.Telegram.user_name(user)

    message =
      "An unauthorized user (#{user_name}) is sending message to fondbot!\n" <>
        "`#{inspect(payload)}`\n\n" <>
        "If you want authorize future messages in that chat, " <>
        "click the botton below"

    keyboard = [
      [{:callback, "Authorize #{user_name}", "guard.auth.#{user_id}"}]
    ]

    Nadia.send_message(
      channel_id,
      message,
      reply_markup: Util.Telegram.keyboard(keyboard)
    )
  end

  defp send_warning(chat_id) do
    Nadia.send_message(
      chat_id,
      "Unauthorized access!\nThis incidence will be reported."
    )
  end

  defp authorized?(user_id, chat_id, %{safe_users: user_ids, report_channel: channel_id}) do
    user_id in user_ids or chat_id == channel_id
  end

  defp handle_guard_command(
         %CallbackQuery{data: "guard.auth." <> user_id},
         %{safe_users: safe_users, report_channel: channel_id} = guard
       ) do
    user_id = String.to_integer(user_id)
    Nadia.send_message(channel_id, "The user (id=#{user_id}) is authorized")
    {:break, %{guard | safe_users: [user_id | safe_users]}}
  end

  defp handle_guard_command(_, _) do
    :ok
  end
end
