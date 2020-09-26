defmodule Extension.Cleanser do
  use Extension

  import Util.Telegram

  alias Nadia.Model.Message

  @type uri_t :: %{host: any(), path: any(), query: any()}

  def on(%Message{text: text} = m, _) do
    uri = parse_uri(text)

    cond do
      is_nil(uri) -> throw(:skip)
      match?({:error, _, _}, uri) -> throw(:skip)
      is_nil(uri[:scheme]) || is_nil(uri[:host]) -> throw(:skip)
      is_nil(uri[:query]) -> throw(:skip)
      uri[:path] == "" -> throw(:skip)
      true -> :ok
    end

    case cleanse(uri) do
      {:changed, new_uri} ->
        # delete_message(m)

        new_uri = generate_uri(new_uri)
        send_reply(m, text, new_uri)
        throw(:done)

      _ ->
        throw(:skip)
    end
  catch
    :skip -> :ok
    :done -> :ok
  end

  @preset_cleanser [
    :utm,
    :amazon_ref,
    :taobao,
    :jd_ref,
    :jd,
    :amazon
  ]

  @spec cleanse(uri_t()) :: {:ok, uri_t()} | :unchanged
  defp cleanse(uri) do
    @preset_cleanser
    |> Enum.reduce({:cont, uri}, fn
      preset, {:cont, uri} -> cleanse(preset, uri)
      _preset, {:done, uri} -> {:done, uri}
    end)
    |> elem(1)
    |> case do
      new_uri ->
        if uri_eq?(new_uri, uri) do
          :unchanged
        else
          {:changed, new_uri}
        end
    end
  end

  @spec cleanse(atom(), uri_t()) ::
          {:cont, uri_t()}
          | {:done, uri_t()}
  defp cleanse(preset, uri)

  defp cleanse(:utm_cleaner, uri) do
    query = uri[:query]
    query = Enum.reject(query, &match?({"utm_" <> _, _}, &1))
    {:cont, %{uri | query: query}}
  end

  defp cleanse(:taobao, %{host: "s.taobao.com"} = uri),
    do: {:done, filter_query(uri, ["q"])}

  defp cleanse(:taobao, %{path: "/item.htm"} = uri),
    do: {:done, filter_query(uri, ["id"])}

  defp cleanse(:jd, %{host: "item.jd." <> _} = uri),
    do: {:done, filter_query(uri, [])}

  defp cleanse(:jd, %{host: "search.jd." <> _} = uri),
    do: {:done, filter_query(uri, ["keyword"])}

  defp cleanse(:amazon, %{host: "www.amazon." <> _, path: "/dp/" <> _} = uri),
    do: {:done, filter_query(uri, [])}

  defp cleanse(:amazon_ref, %{host: "www.amazon." <> _} = uri) do
    uri
    |> reject_query(fn
      "ref_" <> _ -> true
      "pf_rd_" <> _ -> true
      _ -> false
    end)
    |> case do
      uri -> {:cont, uri}
    end
  end

  defp cleanse(_, uri), do: {:cont, uri}

  defp send_reply(message, old_uri, new_uri) do
    text =
      "<i>The link you sent contains tracking pieces " <>
        "and thus I cleansed it for you.</i>\n\n" <>
        "Original: <s>#{escape(old_uri, :html)}</s>\n\n" <>
        "Cleansed: #{escape(new_uri, :html)}"

    buttons = [
      [
        {:url, "Visit original", old_uri},
        {:url, "Visit cleansed", new_uri}
      ]
    ]

    reply(
      message,
      text,
      disable_web_page_preview: true,
      reply_markup: keyboard(:inline, buttons),
      parse_mode: "HTML"
    )
  end

  defp parse_uri(text) when not is_binary(text), do: nil

  defp parse_uri(text) do
    map = :uri_string.parse(text)
    query = map[:query] || ""
    Map.put(map, :query, :uri_string.dissect_query(query))
  end

  defp generate_uri(map) do
    map =
      case map[:query] do
        [] -> Map.delete(map, :query)
        q -> %{map | query: :uri_string.compose_query(q)}
      end

    :uri_string.recompose(map)
  end

  defp reject_query(uri, denied_keys) when is_list(denied_keys) do
    reject_query(uri, &(&1 in denied_keys))
  end

  defp reject_query(uri, fun) do
    query = Enum.reject(uri[:query], fn {k, _} -> fun.(k) end)
    %{uri | query: query}
  end

  defp filter_query(uri, allowed_keys) do
    query = Enum.filter(uri[:query], fn {k, _} -> k in allowed_keys end)
    %{uri | query: query}
  end

  defp uri_eq?(uri1, uri2) do
    uri1 == uri2
  end
end
