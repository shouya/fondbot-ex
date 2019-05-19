defmodule Extension.Fetcher do
  @moduledoc """
  Inline bot that fetches pictures (or other media files for you)
  """

  use Extension

  alias Nadia.Model.InlineQuery
  alias Util.InlineResultCollector

  def on(%InlineQuery{query: text} = q, _) do
    case :uri_string.parse(text) do
      {:error, _, _} ->
        nil

      %{host: h} when is_binary(h) ->
        spawn(fn -> handle_url(q, text) end)
    end

    :ok
  end

  @spec handle_url(InlineQuery.t(), binary()) :: :ok
  def handle_url(q, url) do
    url_map = :uri_string.parse(url)
    type = determine_type(url_map)

    if is_nil(type) do
      :ok
    else
      entity = get_entity(type, url)
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
