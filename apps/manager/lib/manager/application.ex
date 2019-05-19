defmodule Manager.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  import Supervisor.Spec

  alias Manager.{ExtStack, ExtSupervisor, Updater}

  require Logger

  @updater Application.fetch_env!(:manager, :updater)
  def start(_type, _args) do
    exts = Application.fetch_env!(:manager, :exts)

    Logger.info("Using updater #{@updater}")
    updater_children =
      case @updater do
        :poll -> [Updater.Poll]
        :webhook -> [Updater.Webhook]
      end

    children =
      [
        supervisor(ExtSupervisor, [exts]),
        worker(ExtStack, [exts])
      ] ++ updater_children

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Manager.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
