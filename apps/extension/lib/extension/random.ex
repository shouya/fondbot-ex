defmodule Extension.Random do
  use Extension

  alias Nadia.Model.{CallbackQuery, Message}

  import Util.Telegram

  @impl true
  def on(%Message{text: "/rand"} = m, _) do
    btns = [
      {:callback, "🎲", "random.roll"},
      {:callback, "✊🖐✌️", "random.rps"},
      {:callback, "[0,1)", "random.0.0-1.0"}
    ]

    reply(
      m,
      "Use the buttons below to generate something random",
      reply_markup: keyboard(:inline, [btns])
    )
  end

  def on(%CallbackQuery{data: "random.0.0-1.0"} = q, _) do
    rand = :rand.uniform() |> :erlang.float_to_binary(decimals: 4)
    reveal(q, "[0,1)", rand)
  end

  def on(%CallbackQuery{data: "random.roll"} = q, _) do
    rand = ~w"1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣" |> Enum.random()
    reveal(q, "1..6", rand)
  end

  def on(%CallbackQuery{data: "random.rps"} = q, _) do
    rand = ["✊", "🖐", "✌️"] |> Enum.random()
    reveal(q, "✊/🖐/✌️", rand)
  end

  defp reveal(%CallbackQuery{from: from} = q, info, num) do
    answer(q)
    name = user_name(from) |> escape(:markdown)

    text = """
    *#{name}* got: #{num} (_out of #{info |> escape(:markdown)}_).
    """

    reply(q.message, text, parse_mode: "Markdown")
  end
end
