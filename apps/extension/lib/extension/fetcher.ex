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

      %{} ->
        nil
    end

    :ok
  end

  @spec handle_url(InlineQuery.t(), binary()) :: :ok
  def handle_url(q, url) do
    case determine_type(q.id, url) do
      nil ->
        :ok

      type ->
        entity = get_entity(type, url)
        InlineResultCollector.add(q.id, [entity])
        :ok
    end
  end

  defp determine_type(id, url) do
    url_map = :uri_string.parse(url)

    case determine_type_by_ext(url_map.path) do
      nil ->
        InlineResultCollector.extend(id, 3000)
        determine_type_by_mime(url)

      type ->
        type
    end
  end

  @ext_type_map %{
    photo: [".jpg", ".png", ".gif", ".jpeg"]
  }
  defp determine_type_by_ext(path) do
    @ext_type_map
    |> Enum.find({nil, nil}, fn {_k, exts} ->
      String.ends_with?(path, exts)
    end)
    |> elem(0)
  end

  @req_header [
    {"User-Agent",
     "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.14; rv:66.0) Gecko/20100101 Firefox/66.0"},
    {"Accept", "*/*"}
  ]

  @mime_type_map %{
    photo: ["image/png", "image/jpeg", "image/webp", "image/bmp"]
  }
  defp determine_type_by_mime(url) do
    case :hackney.request(:get, url, @req_header, "", follow_redirect: true) do
      {:error, _} ->
        nil

      {:ok, code, headers, _} when 200 <= code and code <= 299 ->
        case headers |> Map.new() |> Map.get("Content-Type") do
          nil ->
            nil

          content_type ->
            @mime_type_map
            |> Enum.find({nil, nil}, fn {_k, mime_types} ->
              Enum.any?(mime_types, &(content_type == &1))
            end)
            |> elem(0)
        end

      _ ->
        nil
    end
  end

  defp get_entity(type, url)

  defp get_entity(:photo, url) do
    %Nadia.Model.InlineQueryResult.Photo{
      type: "photo",
      photo_url: url,
      thumb_url: url,
      id: Nanoid.generate(),
      description: "Send Photo"
    }
  end
end
