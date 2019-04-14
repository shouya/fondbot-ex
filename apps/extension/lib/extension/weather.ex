defmodule Extension.Weather do
  use Extension
  require Logger

  alias Nadia.Model.{Message, CallbackQuery}
  alias Extension.Weather.Provider.AirVisual

  defstruct [:cities, :pending]

  def new() do
    %__MODULE__{
      cities: [],
      pending: nil
    }
  end

  def on(
        %Message{location: %{} = longlat} = msg,
        %{cities: cities, pending: pending} = state
      )
      when not is_nil(pending) do
    %{longitude: long, latitude: lat} = longlat

    case AirVisual.get_nearst_city({long, lat}) do
      {:ok, {id, city_name}} ->
        city = %{name: city_name, loc: [long, lat], city_id: id}

        Util.Telegram.reply(
          msg,
          "Location added for #{city_name} (#{long}, #{lat})",
          reply_markup: Util.Telegram.reply_markup(:remove)
        )

        {:ok, %{state | cities: [city | cities], pending: nil}}

      {:error, e} ->
        Util.Telegram.reply(
          msg,
          "Unable to find city near (#{long}, #{lat})\n\n#{inspect(e)}",
          reply_markup: Util.Telegram.reply_markup(:remove)
        )

        {:ok, %{state | pending: nil}}
    end
  end

  def on(%Message{text: "Cancel"} = msg, %{pending: pending} = state)
      when not is_nil(pending) do
    Util.Telegram.say(
      msg,
      "Nevermind.",
      reply_markup: Util.Telegram.reply_markup(:remove)
    )

    {:ok, %{state | pending: nil}}
  end

  def on(%Message{} = msg, state) do
    {:ok, chat_id} = Util.Telegram.chat_id(msg)

    case Util.Telegram.command(msg) do
      "weather" -> weather_report(chat_id, state)
      {"add_loc", loc} -> add_location(chat_id, loc, state)
      "add_loc" -> add_location(chat_id, state)
      "del_loc" -> remove_location(chat_id, state)
      _ -> :ok
    end
  end

  def on(%CallbackQuery{data: "weather.del_loc.all"} = q, state) do
    Util.Telegram.edit(q, text: "All locations deleted")
    {:ok, Map.put(state, :cities, [])}
  end

  def on(%CallbackQuery{data: "weather.del_loc." <> del_city} = q, state) do
    Util.Telegram.edit(q, text: "Location #{del_city} deleted")

    {:ok,
     Map.update!(state, :cities, fn %{name: city} ->
       String.downcase(city) == String.downcase(del_city)
     end)}
  end

  def weather_report(chat_id, %{cities: []}) do
    Nadia.send_message(
      chat_id,
      "No city registered\nPlease add some cities using /add_loc"
    )

    :ok
  end

  def weather_report(chat_id, state) do
    Nadia.send_chat_action(chat_id, "typing")

    state
    |> Map.get(:cities)
    |> Enum.map(fn %{city_id: city_id, name: name} ->
      spawn(fn ->
        case AirVisual.weather_report(city_id) do
          {:ok, report} ->
            Nadia.send_message(chat_id, report, parse_mode: "Markdown")

          {:error, e} ->
            Nadia.send_message(
              chat_id,
              "Unable get weather report for #{name}\n\n#{inspect(e)}"
            )
        end
      end)
    end)

    :ok
  end

  def add_location(chat_id, loc, state) do
    case AirVisual.search_city(loc) do
      {:ok, {id, name}} ->
        Nadia.send_message(chat_id, "Location added (#{name}).")
        city = %{name: name, city_id: id}
        {:ok, Map.update!(state, :cities, &[city | &1])}

      {:error, e} ->
        Nadia.send_message(chat_id, "Unable to find city #{loc}\n#{inspect(e)}")
        :ok
    end
  end

  def add_location(chat_id, state) do
    keyboard =
      Util.Telegram.keyboard(
        :reply,
        [[{:request_location, "Send location"}, "Cancel"]]
      )

    Nadia.send_message(
      chat_id,
      "Send me a location",
      reply_markup: keyboard
    )

    pending = %{}

    {:ok, %{state | pending: pending}}
  end

  def remove_location(chat_id, %{cities: cities}) do
    keyboard =
      Util.Telegram.keyboard(:inline, [
        [{:callback, "All locations", "weather.del_loc.all"}] ++
          Enum.map(cities, &{:callback, &1.name, "weather.del_loc." <> &1.name})
      ])

    Nadia.send_message(
      chat_id,
      "Which location do you want to remove?",
      reply_markup: keyboard
    )

    :ok
  end
end

defmodule Extension.Weather.Provider.AirVisual do
  @endpoint "https://website-api.airvisual.com/"

  @query_params [
    {"units.temperature", "celsius"},
    {"units.distance", "kilometer"},
    {"AQI", "US"}
  ]

  def get_nearst_city({long, lat}) do
    case request(:get, "v1/cities/nearest/by/coordinates/#{lat}/#{long}") do
      {:ok, %{"url" => path, "id" => id}} ->
        city = path |> String.split("/") |> List.last() |> String.capitalize()
        {:ok, {id, city}}

      {:error, e} ->
        {:error, e}
    end
  end

  def search_city(name) do
    case request(:get, "v1/search", params: [q: name]) do
      {:ok, %{"cities" => []}} ->
        {:error, :city_not_found}

      {:ok, %{"cities" => [city]}} ->
        %{"name" => name, "id" => id} = city
        {:ok, {id, name}}

      {:error, e} ->
        {:error, e}

      {:ok, e} ->
        {:error, {:mismatch, e}}
    end
  end

  def weather_report(city_id) do
    with {:ok, %{} = result} <-
           request(:get, "v1/cities/#{city_id}", params: @query_params),
         report <- generate_report(result) do
      {:ok, report}
    else
      {:error, e} -> {:error, e}
    end
  end

  defp request(method, path, opts \\ []) do
    url = :hackney_url.make_url(@endpoint, path, Keyword.get(opts, :params, []))

    with {:ok, 200, _resp_headers, body_ref} <- :hackney.request(method, url),
         {:ok, body} <- :hackney.body(body_ref),
         {:ok, map} <- Poison.decode(body) do
      {:ok, map}
    else
      {:ok, e} -> {:error, {:mismatch, e}}
      {:error, e} -> {:error, e}
    end
  end

  defmodule Condition do
    defstruct [:ts, :aqi, :temperature, :humidity, :condition]
  end

  defp generate_report(data) do
    %{
      "current" => current,
      "forecasts" => %{"hourly" => forecasts},
      "name" => city_name,
      "recommendations" => %{"pollution" => recommends}
    } = data

    current = parse_condition(current)
    forecast = Enum.map(forecasts, &parse_condition/1) |> Enum.drop(1) |> Enum.take(12)

    recommends =
      recommends
      |> Map.values()
      |> Enum.map(&Map.get(&1, "text"))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn v -> " - #{v}" end)
      |> Enum.join("\n")

    report =
      ["Conditions", "Temperature", "Humidity", "AQI"]
      |> Enum.map(fn criterion ->
        "**#{criterion}**: " <> generate_report(criterion, current, forecast)
      end)
      |> Enum.join("\n")

    "Weather report for #{city_name} " <>
      "(updated #{Util.Time.humanize(current.ts)})\n\n" <>
      report <>
      "\n\n" <>
      recommends
  end

  defp generate_report("Conditions", current, forecasts) do
    [current | forecasts]
    |> Enum.map(fn %{condition: c} -> c end)
    |> Enum.map(&condition_icon/1)
    |> Enum.dedup()
    |> Enum.join("→")
  end

  defp generate_report("Temperature", current, forecasts) do
    all = [current | forecasts] |> Enum.map(fn %{temperature: t} -> t end)
    {min, max} = all |> Enum.min_max()
    curr = hd(all)
    "#{curr}℃ (#{min}—#{max}℃)"
  end

  defp generate_report("Humidity", current, forecasts) do
    all = [current | forecasts] |> Enum.map(fn %{humidity: t} -> t end)
    {min, max} = all |> Enum.min_max()
    curr = hd(all)
    "#{curr}% (#{min}—#{max}%)"
  end

  defp generate_report("AQI", current, forecasts) do
    all = [current | forecasts] |> Enum.map(fn %{aqi: t} -> t end)
    {min, max} = all |> Enum.min_max()
    curr = hd(all)
    "#{curr}, #{aqi_desc(curr)} (#{min}—#{max})"
  end

  defp aqi_desc(aqi) when 0 <= aqi and aqi < 50, do: "Good"
  defp aqi_desc(aqi) when 50 <= aqi and aqi < 100, do: "Moderate"
  defp aqi_desc(aqi) when 100 <= aqi and aqi < 150, do: "Unhealthy for Sensitve Groups"
  defp aqi_desc(aqi) when 150 <= aqi and aqi < 200, do: "Unhealthy"
  defp aqi_desc(aqi) when 200 <= aqi and aqi < 300, do: "Very Unhealthy"
  defp aqi_desc(aqi) when 300 <= aqi, do: "Hazardous"

  defp condition_icon(text) do
    case text do
      "clear-sky" -> "☀️"
      _ -> text
    end
  end

  defp parse_condition(%{
         "ts" => ts,
         "aqi" => aqi,
         "temperature" => temperature,
         "humidity" => humidity,
         "condition" => condition
       }) do
    %Condition{
      ts: Timex.parse!(ts, "{ISO:Extended}"),
      aqi: aqi,
      temperature: temperature,
      humidity: humidity,
      condition: condition
    }
  end
end
