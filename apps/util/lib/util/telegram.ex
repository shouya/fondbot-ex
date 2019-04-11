defmodule Util.Telegram do
  alias Nadia.Model.{
    Message,
    Chat,
    User,
    CallbackQuery,
    InlineKeyboardMarkup,
    InlineKeyboardButton
  }

  @spec user_name(Nadia.Model.User.t()) :: bitstring()
  def user_name(%User{first_name: first, last_name: last, username: name}) do
    first || last || name || "unnamed"
  end

  @spec chat_id(any()) :: {:error, :no_chat_id} | {:ok, any()}
  def chat_id(%Message{chat: %Chat{id: id}}), do: {:ok, id}
  def chat_id(%CallbackQuery{message: msg}), do: chat_id(msg)
  def chat_id(_), do: {:error, :no_chat_id}

  @spec from_user(any()) :: {:ok, User.t()}
  def from_user(%Message{from: user}), do: {:ok, user}
  def from_user(%CallbackQuery{from: user}), do: {:ok, user}
  def from_user(_), do: {:error, :no_from_user}

  @spec command(any()) :: :not_command | binary() | {binary(), [binary()]}
  def command(%Message{text: "/" <> text}) do
    case String.split(text, " ", trim: true) do
      [cmd] -> cmd
      [cmd | args] -> {cmd, args}
    end
  end

  def command(_), do: :not_command

  def keyboard(btns, opts \\ []) when is_list(btns) do
    kbd = Enum.map(btns, fn row -> Enum.map(row, &inline_button/1) end)

    %InlineKeyboardMarkup{inline_keyboard: kbd}
    |> Map.merge(Enum.into(opts, %{}))
  end

  def inline_button({:callback, text, data}) do
    %InlineKeyboardButton{callback_data: data, text: text}
  end

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
