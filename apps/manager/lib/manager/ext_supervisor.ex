defmodule Manager.ExtSupervisor do
  use Supervisor

  def start_link(exts) do
    Supervisor.start_link(__MODULE__, exts)
  end

  def init(exts) do
    children = exts |> Enum.map(fn mod -> {mod, []} end)
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Manager.Supervisor]
    Supervisor.init(children, opts)
  end
end
