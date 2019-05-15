defmodule Manager.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  import Supervisor.Spec

  alias Manager.{ExtStack, ExtSupervisor, Updater}

  @updater Application.fetch_env!(:manager, :updater)
  @webhook_port Application.get_env(:manager, :webhook, 9786)
  def start(_type, _args) do
    exts = Application.fetch_env!(:manager, :exts)

    updater_children =
      case @updater do
        :poll ->
          [Updater.Poll]

        :webhook ->
          [
            Plug.Cowboy.child_spec(
              scheme: :http,
              plug: Updater.Webhook,
              options: [port: @webhook_port]
            )
          ]
      end

    children = [
      supervisor(ExtSupervisor, [exts]),
      worker(ExtStack, [exts])
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Manager.Supervisor]
    Supervisor.start_link(children ++ updater_children, opts)
  end
end
