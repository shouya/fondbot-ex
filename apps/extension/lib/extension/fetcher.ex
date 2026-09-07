defmodule Extension.Fetcher do
  @moduledoc """
  Inline bot that fetches pictures (or other media files for you)
  """

  use Extension

  alias Nadia.Model.{InlineQuery, InlineQueryResult}
  alias Util.InlineResultCollector

  def on(%InlineQuery{query: text} = q, _) do
    # The address check needs DNS, so it happens off the extension process.
    if Util.Url.http_link?(text) do
      spawn(fn -> handle_url(q, text) end)
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
    path = URI.parse(url).path || ""

    case determine_type_by_ext(path) do
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

  # Redirects are followed by hand so that every hop is checked against
  # Util.Url; hackney's follow_redirect would only check the first one.
  @http_opts [connect_timeout: 5_000, recv_timeout: 5_000, follow_redirect: false]
  @redirect_limit 3

  @mime_type_map %{
    photo: ["image/png", "image/jpeg", "image/webp", "image/bmp"]
  }

  defp determine_type_by_mime(url, redirects_left \\ @redirect_limit)

  defp determine_type_by_mime(_url, 0), do: nil

  defp determine_type_by_mime(url, redirects_left) do
    case request(url) do
      {:ok, code, headers} when 200 <= code and code <= 299 ->
        mime_to_type(content_type(headers))

      {:ok, code, headers} when 300 <= code and code <= 399 ->
        follow_redirect(url, headers, redirects_left)

      _ ->
        nil
    end
  end

  defp follow_redirect(url, headers, redirects_left) do
    case header(headers, "location") do
      nil ->
        nil

      location ->
        determine_type_by_mime(URI.merge(url, location) |> to_string(), redirects_left - 1)
    end
  end

  @spec request(binary()) :: {:ok, integer(), list()} | {:error, any()}
  defp request(url) do
    with {:ok, _uri} <- Util.Url.public_http(url),
         {:ok, code, headers, ref} <- :hackney.request(:get, url, @req_header, "", @http_opts) do
      # Nothing here reads the body, and an unread body leaks the connection.
      :hackney.close(ref)
      {:ok, code, headers}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp content_type(headers) do
    case header(headers, "content-type") do
      nil -> nil
      value -> value |> String.split(";") |> hd() |> String.trim() |> String.downcase()
    end
  end

  defp header(headers, name) do
    case Enum.find(headers, fn {k, _} -> String.downcase(to_string(k)) == name end) do
      nil -> nil
      {_, value} -> to_string(value)
    end
  end

  defp mime_to_type(nil), do: nil

  defp mime_to_type(mime) do
    Enum.find_value(@mime_type_map, fn {type, mimes} -> if mime in mimes, do: type end)
  end

  defp get_entity(type, url)

  defp get_entity(:photo, url) do
    %InlineQueryResult.Photo{
      type: "photo",
      photo_url: url,
      thumb_url: url,
      id: Nanoid.generate(),
      description: "Send Photo"
    }
  end
end
