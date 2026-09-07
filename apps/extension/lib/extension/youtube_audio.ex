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

  @default_instance "https://invidious.namazso.eu"

  @spec instance() :: binary()
  def instance do
    Application.get_env(:extension, :invidious_instance, @default_instance)
  end

  def on(%InlineQuery{query: input} = q, _) do
    case extract_youtube_video_id(String.trim(input)) do
      {:ok, vid} ->
        # Two round trips to a third party must not block the extension.
        InlineResultCollector.extend(q.id, 3000)
        spawn(fn -> answer_with_audio(q.id, vid) end)
        :ok

      {:error, _} ->
        :skip
    end
  end

  def on(_query, _state), do: :skip

  @spec answer_with_audio(binary(), binary()) :: :ok
  def answer_with_audio(query_id, vid) do
    with {:ok, metadata} <- fetch_metadata(vid),
         {:ok, direct_url} <- fetch_direct_url(vid),
         {:ok, result} <- to_query_result(vid, metadata, direct_url) do
      InlineResultCollector.add(query_id, [result])
    end

    :ok
  end

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

  @req_opts [
    receive_timeout: 5_000,
    connect_options: [timeout: 3_000],
    retry: false
  ]

  @spec fetch_direct_url(binary()) :: {:ok, binary()} | {:error, any}
  def fetch_direct_url(vid) do
    instance = instance()

    resp =
      Req.post(
        "#{instance}/download",
        [
          form: [
            id: vid,
            title: "bazbar",
            download_widget: ~s[{"itag":140,"ext":"m4a"}]
          ],
          follow_redirects: false
        ] ++ @req_opts
      )

    with {:ok, resp} <- resp,
         [real_url] <- Req.Response.get_header(resp, "location") do
      {:ok, "#{instance}#{real_url}"}
    else
      _ -> {:error, "failed to fetch direct link"}
    end
  end

  @spec fetch_metadata(binary()) :: {:ok, map()} | {:error, any}
  def fetch_metadata(vid) do
    resp = Req.get("#{instance()}/api/v1/videos/#{vid}", @req_opts)

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
