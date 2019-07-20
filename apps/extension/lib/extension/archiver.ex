defmodule Extension.Archiver do
  use Extension

  alias Nadia.Model.{CallbackQuery, InlineQuery, Message, User}

  def on(%Message{text: "/archive " <> url}) do
  end

  defp validate_link(url) do
  end

  defp archive_link(url) do
    [:archive_org]
    |> Task.async_stream(fn archiver ->
      archive_link(archiver, url)
    end)
  end

  defp archive_link(:archive_org, link) do
    url = "https://web.archive.org/web/*/" <> link
    {:ok, code, _headers, ref} = :hackney.get(url, [], "", follow_redirect: true)
    :hackney.skip_body(ref)
  end

  defp archive_link(:archive_today, link) do
    url = "https://archive.today/submit/"
    data = [{"url", link}, {"anyway", "1"}]

    {:ok, code, headers, ref} =
      :hackney.post(
        url,
        [],
        {:form, data},
        follow_redirect: true
      )

    :hackney.skip_body(ref)
  end

  defp archive(url) do
    with {:ok, url} = validate_link(url) do
    end
  end
end
