defmodule Util.Telegram do
  alias Nadia.Model.{
    Message,
    Chat,
    User,
    CallbackQuery,
    InlineQuery,
    InlineKeyboardMarkup,
    InlineKeyboardButton,
    ReplyKeyboardMarkup,
    ReplyKeyboardRemove,
    ForceReply,
    KeyboardButton
  }

  @spec user_name(Nadia.Model.User.t()) :: bitstring()
  def user_name(%User{first_name: first, last_name: last, username: name}) do
    first || last || name || "unnamed"
  end

  @spec chat_id(any()) :: {:ok, any()} | {:error, :no_chat_id}
  def chat_id(%Message{chat: %Chat{id: id}}), do: {:ok, id}
  def chat_id(%CallbackQuery{message: msg}), do: chat_id(msg)
  def chat_id(_), do: {:error, :no_chat_id}

  @spec from_user(any()) :: {:ok, User.t()} | {:error, :no_from_user}
  def from_user(%Message{from: user}), do: {:ok, user}
  def from_user(%CallbackQuery{from: user}), do: {:ok, user}
  def from_user(%InlineQuery{from: user}), do: {:ok, user}
  def from_user(_), do: {:error, :no_from_user}

  @spec command(any()) :: :not_command | binary() | {binary(), [binary()]}
  def command(%Message{text: "/" <> text}) do
    case String.split(text, " ", trim: true) do
      [cmd] -> cmd
      [cmd | args] -> {cmd, args}
    end
  end

  def command(_), do: :not_command

  def reply_markup(action, opts \\ [])

  def reply_markup(:force_reply, opts) do
    force_reply(opts)
  end

  def reply_markup(:remove, opts) do
    remove_keyboard(opts)
  end

  def reply_markup(:hide, opts) do
    remove_keyboard(opts)
  end

  def force_reply(_opts \\ []) do
    %ForceReply{selective: true, force_reply: true}
  end

  def remove_keyboard(opts \\ []) do
    %ReplyKeyboardRemove{
      remove_keyboard: true,
      selective: Keyword.get(opts, :selective, false)
    }
  end

  def keyboard(type, btns, opts \\ [])

  def keyboard(:reply, btns, opts) when is_list(btns) do
    kbd = Enum.map(btns, fn row -> Enum.map(row, &keyboard_button/1) end)

    %ReplyKeyboardMarkup{keyboard: kbd}
    |> Map.merge(Enum.into(opts, %{}))
  end

  def keyboard(:inline, btns, opts) when is_list(btns) do
    kbd = Enum.map(btns, fn row -> Enum.map(row, &inline_button/1) end)

    %InlineKeyboardMarkup{inline_keyboard: kbd}
    |> Map.merge(Enum.into(opts, %{}))
  end

  def inline_button({:callback, text, data}) do
    %InlineKeyboardButton{callback_data: data, text: text}
  end

  def inline_button({:url, text, url}) do
    %InlineKeyboardButton{url: url, text: text}
  end

  def keyboard_button({:request_location, text}) do
    %KeyboardButton{request_location: true, text: text}
  end

  def keyboard_button(text) when is_bitstring(text) do
    keyboard_button({:text, text})
  end

  def keyboard_button({:text, text}) do
    %KeyboardButton{text: text}
  end

  def answer(%CallbackQuery{id: id}, opts \\ []) do
    spawn(fn -> Nadia.answer_callback_query(id, opts) end)
  end

  def say(msg, request) do
    say(msg, request, [])
  end

  def reply(%Message{message_id: id} = msg, request, opts \\ []) do
    say(msg, request, [{:reply_to_message_id, id} | opts])
  end

  def say(msg, {:audio, audio}, opts) do
    say(msg, :send_audio, [audio], opts)
  end

  def say(msg, {:location, lat, long}, opts) do
    say(msg, :send_location, [lat, long], opts)
  end

  def say(msg, {:photo, photo}, opts) do
    say(msg, :send_photo, [photo], opts)
  end

  def say(msg, text, opts) when is_bitstring(text) do
    say(msg, :send_message, [text], opts)
  end

  defp say(%Message{chat: %{id: chat_id}}, func, args, opts) do
    apply(Nadia, func, [chat_id | args] ++ [opts])
  end

  def edit(msg, reply_markup: reply_markup) do
    edit(msg, :edit_message_reply_markup, [], reply_markup: reply_markup)
  end

  def edit(msg, [{:caption, caption} | opts]) do
    edit(msg, :edit_message_caption, [caption], opts)
  end

  def edit(msg, [{:text, text} | opts]) do
    edit(msg, :edit_message_text, [text], opts)
  end

  defp edit(%CallbackQuery{message: msg}, func, args, opts) do
    edit(msg, func, args, opts)
  end

  defp edit(%Message{chat: %{id: chat_id}, message_id: id}, func, args, opts) do
    apply(Nadia, func, [chat_id, id, nil | args] ++ [Enum.into(opts, [])])
  end

  # Like edit, but promote to the latest one, return the new message
  # done by deleting and resending
  def reset(stuff, request, opts \\ [])

  def reset(%CallbackQuery{message: msg}, request, opts) do
    reset(msg, request, opts)
  end

  def reset(%Message{} = msg, request, opts) do
    delete_message(msg)
    say(msg, request, opts)
  end

  def delete_message(%Message{chat: %{id: chat_id}, message_id: id}) do
    Nadia.API.request("deleteMessage", chat_id: chat_id, message_id: id)
  end

  @doc """
  Returns a human-friendly short description about the massage
  """
  def message_digest(%Message{text: text}) when byte_size(text) > 30 do
    shortened = String.slice(text, 0..20)
    ~s("#{shortened}…")
  end

  def message_digest(%Message{text: text}) do
    ~s("#{text}")
  end

  def message_digest(%Message{photo: [_ | _]}) do
    ~s(the photo)
  end

  def message_digest(%Message{video: a}) when not is_nil(a) do
    ~s(the video)
  end

  def message_digest(%Message{voice: a}) when not is_nil(a) do
    ~s(the voice message)
  end

  def message_digest(%Message{}) do
    ~s(the message)
  end

  @doc """
  Reproduce a message
  """
  def reproduce(message, opts \\ [])

  def reproduce(%Message{text: text} = msg, opts) when not is_nil(text) do
    chat_id = opts[:chat_id] || msg.chat.id
    Nadia.send_message(chat_id, text)
  end

  def escape(text, :html) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  def escape(text, :markdown) do
    text
    |> String.replace("*", "\*")
    |> String.replace("_", "\_")
    |> String.replace("[", "\[")
    |> String.replace("]", "\]")
    |> String.replace("(", "\(")
    |> String.replace(")", "\)")
  end

  def remove_command_suffix(%Message{text: t} = m) when is_binary(t) do
    new_t = Regex.replace(~r[^(/\w+)@\w+bot], t, "\\1")
    Map.put(m, :text, new_t)
  end

  def remove_command_suffix(any), do: any

  defguardp begin_with_slash(msg) when binary_part(msg, 0, 1) == "/"
  defguardp follow_with_text(msg, txt) when binary_part(msg, 1, byte_size(txt)) == txt

  defguard is_single_cmd(msg, txt)
           when begin_with_slash(msg) and
                  follow_with_text(msg, txt) and
                  byte_size(msg) == byte_size(txt) + 1

  defguard is_cmd_with_arg(msg, txt)
           when begin_with_slash(msg) and
                  follow_with_text(msg, txt) and
                  binary_part(msg, byte_size(txt) + 1, 1) == " "

  defguard is_cmd(msg, text)
           when is_single_cmd(msg, text) or
                  is_cmd_with_arg(msg, text)
end
