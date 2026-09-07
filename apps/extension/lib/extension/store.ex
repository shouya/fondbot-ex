defmodule Extension.Store do
  @moduledoc """
  The store for extension data must be a GenServer with the following callbacks.
  The store module must be able to store arbitrary Elixir data.

  The store module is specified via extension.store_module config.
  """

  @callback start_link(Keyword.t()) :: {:ok, any()}
  @callback save_state(module(), any()) :: :ok | {:error, any()}
  @callback load_state(module()) :: {:ok, any()} | :undef | {:error, any()}

  def start_link(opts), do: apply(adapter(), :start_link, [opts])

  def save_state(ext, state) do
    if transient?(state) do
      require Logger
      Logger.warning("Not saving state of #{ext}: it contains a pid, ref, port, or fun")
      :ok
    else
      apply(adapter(), :save_state, [ext, state])
    end
  end

  # Pids, refs, ports, and funs do not survive a node restart; a state
  # containing one would poison the store (see load_state's :safe decode).
  defp transient?(term) when is_pid(term), do: true
  defp transient?(term) when is_reference(term), do: true
  defp transient?(term) when is_port(term), do: true
  defp transient?(term) when is_function(term), do: true
  defp transient?(term) when is_list(term), do: Enum.any?(term, &transient?/1)

  defp transient?(term) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.any?(&transient?/1)

  defp transient?(term) when is_map(term) do
    term |> :maps.to_list() |> Enum.any?(fn {k, v} -> transient?(k) or transient?(v) end)
  end

  defp transient?(_), do: false
  def load_state(ext), do: apply(adapter(), :load_state, [ext])

  def adapter do
    Application.get_env(:extension, :store_module, __MODULE__.Dets)
  end
end
