defmodule Extension.Fetcher do
  @moduledoc """
  Inline bot that fetches pictures (or other media files for you)
  """

  use Extension

  alias Nadia.Model.InlineQuery
  alias Util.InlineResultCollector

  def on(%InlineQuery{id: id, query: text} = q, _) do
    case URI.parse(text) do
      %{host: nil} -> nil
      url -> spawn(fn -> handle_url(q, url) end)
    end

    :ok
  end

  @spec handle_url(InlineQuery.t(), URI.t()) :: :ok
  def handle_url(q, url) do
    type = determine_type(url)

    if is_nil(type) do
      :ok
    else
      url_str = URI.to_string(url)
      entity = get_entity(type, url_str)
      InlineResultCollector.add(q.id, [entity])
      :ok
    end
  end

  def determine_type(url) do
    determine_type_by_ext(url.path)
  end

  @ext_type_map %{
    photo: [".jpg", ".png", ".gif", ".jpeg"]
  }
  def determine_type_by_ext(path) do
    @ext_type_map
    |> Enum.find({nil, nil}, fn {_k, exts} ->
      String.ends_with?(path, exts)
    end)
    |> elem(0)
  end

  def get_entity(type, url)

  def get_entity(:photo, url) do
    %Nadia.Model.InlineQueryResult.Photo{
      type: "photo",
      photo_url: url,
      thumb_url: url,
      id: Nanoid.generate(),
      title: "Send Photo"
    }
  end
end
