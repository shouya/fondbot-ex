defmodule Manager.ExtSupervisor do
  use Supervisor

  def start_link(exts) do
    Supervisor.start_link(__MODULE__, exts)
  end

  @extra_sup Application.compile_env(:manager, :extra_supervisors, [])

  def init(exts) do
    children = exts |> Enum.map(fn mod -> {mod, []} end)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    Supervisor.init(@extra_sup ++ children, strategy: :one_for_one)
  end
end
