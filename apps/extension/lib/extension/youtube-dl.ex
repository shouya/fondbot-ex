defmodule Extension.YoutubeDL do
  use Extension, preset: :transient

  import Util.Telegram

  alias Nadia.Model.{Message, CallbackQuery}

  @impl Extension
  def new() do
    %{}
  end

  @impl Extension
  def on(%Message{text: "/dl " <> url, from: user} = m, sessions) do
    session = sessions[user.id]
  end

  def validate_link(url) do
    case URI.parse(url) do
      %{scheme: http} when http in ["https", "http"] -> {:ok, url}
      _ -> {:error, "Invalid url [#{url}]"}
    end
  end
end
