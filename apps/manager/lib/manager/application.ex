defmodule Manager.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  import Supervisor.Spec

  alias Manager.{ExtStack, ExtSupervisor, Updater}

  def start(_type, _args) do
    exts = Application.fetch_env!(:manager, :exts)

    children = [
      supervisor(ExtSupervisor, [exts]),
      {ExtStack, [exts]},
      {Updater.Poll, [{ExtStack, :handler}]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Manager.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
