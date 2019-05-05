defmodule Util.Time do
  @time_conf Application.get_env(:util, :time, timezone: "Asia/Shanghai")

  def now() do
    DateTime.utc_now() |> to_local()
  end

  @spec to_local(DateTime.t()) :: DateTime.t()
  def to_local(datetime) do
    timezone = @time_conf |> Keyword.get(:timezone)
    Timex.Timezone.convert(datetime, timezone)
  end

  @spec format_exact(DateTime.t()) :: bitstring()
  def format_exact(datetime) do
    datetime |> Timex.format!("{ISOdate} {0h24}:{0m}:{0s}")
  end

  @spec humanize(DateTime.t()) :: bitstring()
  def humanize(datetime) do
    Timex.format!(datetime, "{relative}", :relative)
  end

  @spec format_exact_and_humanize(DateTime.t()) :: bitstring()
  def format_exact_and_humanize(datetime) do
    :erlang.iolist_to_binary([
      format_exact(datetime),
      [" (", humanize(datetime), ")"]
    ])
  end

  def format_short_date(datetime) do
    Timex.format!(datetime, "{Mshort} {0D}")
  end

  def format_short_time(datetime) do
    Timex.format!(datetime, "{0h24}:{0m}")
  end
end
