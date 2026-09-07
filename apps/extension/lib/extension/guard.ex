defmodule Extension.Guard do
  use Extension

  alias Nadia.Model.{CallbackQuery, InlineQuery, User}
  alias Util.AssocList

  import Util.Telegram

  defstruct [:safe_users, :report_channel, :pending, :blacklist, :last_report]

  @max_pending 10

  # An unauthorized sender costs the admin channel a forward plus a
  # message, so reporting has to stay rate limited.
  @report_interval_sec 60

  @impl true
  def new() do
    case Application.fetch_env(:extension, :guard) do
      {:ok, conf} ->
        report_channel = conf |> Keyword.fetch!(:report_channel) |> to_chat_id()

        safe_users =
          [report_channel]
          |> Enum.concat(Keyword.get(conf, :safe_users, []))
          |> Enum.map(&to_chat_id/1)

        %__MODULE__{
          safe_users: safe_users,
          report_channel: report_channel,
          pending: [],
          blacklist: [],
          last_report: nil
        }

      :error ->
        :no_guard
    end
  end

  # A state saved before a field existed decodes as a map without it.
  @impl true
  def from_saved(:no_guard), do: :no_guard
  def from_saved(%{} = saved), do: struct(__MODULE__, Map.delete(saved, :__struct__))
  def from_saved(_), do: new()

  @spec to_chat_id(binary() | integer()) :: binary() | integer()
  defp to_chat_id(id) when is_integer(id), do: id

  defp to_chat_id(str) when is_binary(str) do
    case Integer.parse(str) do
      {id, ""} -> id
      _ -> str
    end
  end

  @impl true
  def on(_payload, :no_guard) do
    :ok
  end

  # can't check on inline
  @impl true
  def on(%InlineQuery{from: user}, guard) do
    if authorized?(user.id, nil, guard) and not blocked?(user.id, guard) do
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
        cond do
          blocked?(user_id, guard) ->
            :break

          authorized?(user_id, chat_id, guard) ->
            handle_guard_command(payload, guard)

          already_pending?(user_id, guard) or reported_recently?(guard) ->
            :break

          true ->
            report_and_warn(payload, user, chat_id, guard)
        end
    end
  end

  defp report_and_warn(payload, %{id: user_id} = user, chat_id, guard) do
    confirmation = report_incidence(payload, user, guard)

    new_pending =
      guard
      |> Map.get(:pending)
      |> Enum.take(@max_pending - 1)
      |> AssocList.put(user_id, confirmation)

    send_warning(chat_id)

    {:break, %{guard | pending: new_pending, last_report: DateTime.utc_now()}}
  end

  defp report_incidence(payload, %{id: user_id} = user, %{report_channel: channel_id}) do
    user_name = Util.Telegram.user_name(user)

    forward(payload, channel_id)

    message =
      "An unauthorized user (#{user_name}) is sending message to fondbot!\n" <>
        "If you want authorize future messages in that chat, " <>
        "click the botton below"

    keyboard = [
      [
        {:callback, "Authorize #{user_name}", "guard.auth.#{user_id}"},
        {:callback, "Reject", "guard.reject.#{user_id}"}
      ]
    ]

    say(
      channel_id,
      message,
      reply_markup: Util.Telegram.keyboard(:inline, keyboard)
    )

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

  defp blocked?(user_id, %{blacklist: blacklist}), do: user_id in List.wrap(blacklist)

  defp already_pending?(user_id, %{pending: pending}) do
    not is_nil(AssocList.get(List.wrap(pending), user_id))
  end

  defp reported_recently?(%{last_report: nil}), do: false

  defp reported_recently?(%{last_report: at}) do
    DateTime.diff(DateTime.utc_now(), at) < @report_interval_sec
  end

  defp handle_guard_command(
         %CallbackQuery{data: "guard.auth." <> user_id} = q,
         %{report_channel: channel_id} = guard
       ) do
    answer(q)
    user_id = String.to_integer(user_id)
    confirmation = guard |> Map.fetch!(:pending) |> AssocList.get(user_id)
    user_name = confirmation |> Keyword.fetch!(:user) |> Util.Telegram.user_name()
    {:ok, chat_id} = confirmation |> Keyword.fetch!(:from_chat)

    say(channel_id, "The user (name=#{user_name} id=#{user_id}) is authorized")
    say(chat_id, "The admin has authorized access for you, have fun!")

    guard =
      guard
      |> Map.update!(:pending, &AssocList.delete(&1, user_id))
      |> Map.update!(:blacklist, &(List.wrap(&1) -- [user_id]))
      |> Map.update!(:safe_users, &[user_id | &1])

    {:break, guard}
  rescue
    _ ->
      {:break, guard}
  end

  defp handle_guard_command(
         %CallbackQuery{data: "guard.reject." <> user_id} = q,
         %{report_channel: channel_id} = guard
       ) do
    answer(q)
    user_id = String.to_integer(user_id)
    confirmation = guard |> Map.fetch!(:pending) |> AssocList.get(user_id)
    user_name = confirmation |> Keyword.fetch!(:user) |> Util.Telegram.user_name()
    {:ok, chat_id} = confirmation |> Keyword.fetch!(:from_chat)

    say(channel_id, "The user (name=#{user_name} id=#{user_id}) is rejected")
    say(chat_id, "The admin has rejected access from you (#{user_name})")

    guard =
      guard
      |> Map.update!(:pending, &AssocList.delete(&1, user_id))
      |> Map.update!(:safe_users, &(&1 -- [user_id]))
      |> Map.update!(:blacklist, &[user_id | List.wrap(&1)])

    {:break, guard}
  rescue
    _ ->
      {:break, guard}
  end

  defp handle_guard_command(_, _) do
    :ok
  end
end
