defmodule Extension.YoutubeAudio do
  @moduledoc """
  Answer to inline query containing a youtube link with an audio result.
  """
  use Extension

  alias Nadia.Model.{
    InlineQuery,
    InlineQueryResult
  }

  alias Util.InlineResultCollector

  @invidious_instance "https://invidious.namazso.eu"

  def on(%InlineQuery{query: input} = q, _) do
    input = String.trim(input)

    with {:ok, vid} <- extract_youtube_video_id(input),
         {:ok, direct_url} <- fetch_direct_url(vid),
         {:ok, result} <- to_query_result(vid, direct_url) do
      InlineResultCollector.add(q.id, [result])
      :ok
    else
      _ -> :skip
    end
  end

  def on(_query, _state), do: :skip

  @spec extract_youtube_video_id(binary()) :: {:ok, binary()} | {:error, any}
  defp extract_youtube_video_id(input) do
    uri = URI.parse(input)
    query = URI.decode_query(uri.query)

    case uri do
      %{host: "youtu.be", path: "/" <> vid} ->
        {:ok, vid}

      %{host: full, path: "/watch"}
      when full in ["m.youtube.com", "www.youtube.com"] ->
        {:ok, query["v"]}
    end
  rescue
    # it's entirely possible the input is not a url
    _ -> {:error, "not youtube"}
  end

  @spec fetch_direct_url(binary()) :: {:ok, binary()} | {:error, any}
  def fetch_direct_url(vid) do
    resp =
      Req.post("#{@invidious_instance}/download",
        form: [
          id: vid,
          title: "bazbar",
          download_widget: ~s[{"itag":140,"ext":"m4a"}]
        ],
        follow_redirects: false
      )

    with {:ok, resp} <- resp,
         [real_url] <- Req.Response.get_header(resp, "location") do
      {:ok, "#{@invidious_instance}#{real_url}"}
    else
      _ -> {:error, "failed to fetch direct link"}
    end
  end

  @spec to_query_result(binary(), binary()) ::
          {:ok, InlineQueryResult.Audio.t()}
  defp to_query_result(vid, audio_url) do
    audio = %InlineQueryResult.Audio{
      # some random unique id
      id: vid,
      audio_url: audio_url,
      title: "https://www.youtube.com/watch?v=#{vid}"
    }

    {:ok, audio}
  end
end
