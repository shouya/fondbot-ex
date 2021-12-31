defmodule Extension.Store do
  @moduledoc """
  The store for extension data must be a GenServer with the following callbacks.
  The store module must be able to store arbitrary Elixir data.

  The store module is specified via extension.store_module config.
  """

  @behaviour GenServer

  @callback start_link(Keyword.t()) :: {:ok, any()}
  @callback save_state(module(), any()) :: :ok | {:error, any()}
  @callback load_state(module()) :: {:ok, any()} | :undef | {:error, any()}

  def start_link(opts), do: apply(adapter(), :start_link, [opts])

  def save_state(ext, state), do: apply(adapter(), :save_state, [ext, state])
  def load_state(ext), do: apply(adapter(), :load_state, [ext])

  def adapter do
    Application.get_env(:extension, :store_module, __MODULE__.Dets)
  end
end
