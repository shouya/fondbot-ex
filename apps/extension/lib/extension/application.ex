defmodule Extension.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    Confex.resolve_env!(:extension)

    store_adapter = Extension.Store.adapter()

    children = [
      store_adapter,
      Util.InlineResultCollector,
      Task.Supervisor
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Extension.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
