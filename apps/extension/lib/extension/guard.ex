defmodule Extension.Guard do
  use Extension

  alias Nadia.Model.{CallbackQuery, InlineQuery, User}

  import Util.Telegram

  defstruct [:safe_users, :report_channel, :pending, :blacklist]

  @impl true
  def new() do
    case Application.fetch_env(:extension, :guard) do
      {:ok, conf} ->
        report_channel = Keyword.fetch!(conf, :report_channel)

        safe_users =
          [report_channel | Keyword.get(conf, :safe_users, [])]
          |> Enum.map(fn
            str when is_binary(str) ->
              {val, _} = Integer.parse(str)
              val

            other ->
              other
          end)

        %__MODULE__{
          safe_users: safe_users,
          report_channel: report_channel,
          pending: %{},
          blacklist: []
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
  def on(%InlineQuery{from: user}, guard) do
    if authorized?(user.id, nil, guard) do
      :ok
    else
      :break
    end
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
          confirmation = report_incidence(payload, user, guard)

          new_pending =
            guard
            |> Map.get(:pending)
            |> Map.put(user_id, confirmation)

          send_warning(chat_id)
          {:break, %{guard | pending: new_pending}}
        end
    end
  end

  defp report_incidence(payload, %{id: user_id} = user, %{report_channel: channel_id}) do
    user_name = Util.Telegram.user_name(user)

    message =
      "An unauthorized user (#{user_name}) is sending message to fondbot!\n" <>
        "#{inspect(payload)}\n\n" <>
        "If you want authorize future messages in that chat, " <>
        "click the botton below"

    keyboard = [
      [
        {:callback, "Authorize #{user_name}", "guard.auth.#{user_id}"},
        {:callback, "Reject", "guard.reject.#{user_id}"}
      ]
    ]

    say(channel_id, message, reply_markup: Util.Telegram.keyboard(:inline, keyboard))

    [
      user: user,
      payload: payload,
      from_chat: Util.Telegram.chat_id(payload),
      sent_at: DateTime.utc_now()
    ]
  end

  defp send_warning(chat_id) do
    say(chat_id, "Unauthorized access!\nThis incidence will be reported.")
  end

  defp authorized?(user_id, chat_id, %{safe_users: user_ids, report_channel: channel_id}) do
    user_id in user_ids or chat_id == channel_id
  end

  defp handle_guard_command(
         %CallbackQuery{data: "guard.auth." <> user_id} = q,
         %{report_channel: channel_id} = guard
       ) do
    answer(q)
    user_id = String.to_integer(user_id)
    confirmation = guard |> Map.fetch!(:pending) |> Map.get(user_id)
    user_name = confirmation |> Keyword.fetch!(:user) |> Util.Telegram.user_name()
    {:ok, chat_id} = confirmation |> Keyword.fetch!(:from_chat)

    say(channel_id, "The user (name=#{user_name} id=#{user_id}) is authorized")
    say(chat_id, "The admin has authorized access from you (#{user_name}), have fun!")

    guard =
      guard
      |> Map.update!(:pending, &Map.delete(&1, user_id))
      |> Map.update!(:safe_users, &[user_id | &1])

    {:break, guard}
  end

  defp handle_guard_command(
         %CallbackQuery{data: "guard.reject." <> user_id},
         %{report_channel: channel_id} = guard
       ) do
    user_id = String.to_integer(user_id)
    confirmation = guard |> Map.fetch!(:pending) |> Map.get(user_id)
    user_name = confirmation |> Keyword.fetch!(:user) |> Util.Telegram.user_name()
    {:ok, chat_id} = confirmation |> Keyword.fetch!(:from_chat)

    say(channel_id, "The user (name=#{user_name} id=#{user_id}) is rejected")

    say(chat_id, "The admin has rejected access from you (#{user_name})")

    guard =
      guard
      |> Map.update!(:pending, &Map.delete(&1, user_id))
      |> Map.update!(:blacklist, &[user_id | &1])

    {:break, guard}
  end

  defp handle_guard_command(_, _) do
    :ok
  end
end
