defmodule Util.AssocList do
  @moduledoc """
  Like Keyword but doesn't enforce key to be atom.
  """

  @type key :: any()
  @type value :: any()
  @type t :: [{key(), any()}]

  @spec get(t(), key(), value()) :: nil | value()
  def get(list, key, default \\ nil) when is_list(list) do
    case :lists.keyfind(key, 1, list) do
      {^key, value} -> value
      false -> default
    end
  end

  @spec put(t(), key(), value()) :: t()
  def put(list, key, value) when is_list(list) do
    [{key, value} | delete(list, key)]
  end

  @spec delete(t(), key()) :: t()
  def delete(list, key) do
    case :lists.keymember(key, 1, list) do
      true -> delete_key(list, key)
      _ -> list
    end
  end

  defp delete_key([{key, _} | tail], key), do: delete_key(tail, key)
  defp delete_key([{_, _} = pair | tail], key), do: [pair | delete_key(tail, key)]
  defp delete_key([], _key), do: []
end
