defmodule Util.Number do
  @doc "return ordinal number name: 1 -> first, 2 -> second, etc"
  def ordinal(0), do: "zeroth"
  def ordinal(1), do: "first"
  def ordinal(2), do: "second"
  def ordinal(3), do: "third"
  def ordinal(n) when 4 <= rem(n, 100) and rem(n, 100) <= 20, do: "#{n}th"

  def ordinal(n) do
    suffix = fn
      1 -> "st"
      2 -> "nd"
      _ -> "th"
    end

    "#{n}" <> suffix.(rem(n, 10))
  end
end
