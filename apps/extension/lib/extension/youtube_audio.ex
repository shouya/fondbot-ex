defmodule Nadia.Model.InlineQueryResult.MyAudio do
  # redefining the module to add the caption field

  defstruct type: "audio",
            id: nil,
            audio_url: nil,
            title: nil,
            performer: nil,
            audio_duration: nil,
            reply_markup: nil,
            input_message_content: nil,
            caption: nil

  @type t :: %__MODULE__{
          type: binary,
          id: binary,
          audio_url: binary,
          title: binary,
          performer: binary,
          audio_duration: integer,
          reply_markup: InlineKeyboardMarkup.t(),
          input_message_content: InputMessageContent.t(),
          caption: binary
        }
end

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
         {:ok, metadata} <- fetch_metadata(vid),
         {:ok, direct_url} <- fetch_direct_url(vid),
         {:ok, result} <- to_query_result(vid, metadata, direct_url) do
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
    query = if uri.query, do: URI.decode_query(uri.query)

    case uri do
      %{host: "youtu.be", path: "/" <> vid} ->
        {:ok, vid}

      %{host: full, path: "/watch"}
      when full in ["m.youtube.com", "www.youtube.com"] and not is_nil(query) ->
        {:ok, query["v"]}

      _ ->
        {:error, "not youtube"}
    end
  rescue
    # it's entirely possible the input is not a url at all and
    # URI.parse may fail.
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

  @spec fetch_metadata(binary()) :: %{title: binary(), duration: integer()}
  def fetch_metadata(vid) do
    resp = Req.get("#{@invidious_instance}/api/v1/videos/#{vid}")

    with {:ok, %{body: json}} <- resp do
      metadata = %{
        title: json["title"],
        duration: json["lengthSeconds"]
      }

      {:ok, metadata}
    else
      _ -> {:error, "failed to fetch metadata"}
    end
  end

  @spec to_query_result(binary(), map(), binary()) ::
          {:ok, InlineQueryResult.MyAudio.t()}
  defp to_query_result(vid, metadata, audio_url) do
    audio = %InlineQueryResult.MyAudio{
      # id field is required and must be unique
      id: vid,
      audio_url: audio_url,
      title: metadata.title,
      audio_duration: metadata.duration,
      caption: "https://www.youtube.com/watch?v=#{vid}"
    }

    {:ok, audio}
  end
end
