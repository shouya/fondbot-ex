defmodule Manager.Updater.Poll do
  use GenServer

  require Logger

  # :timeout is getUpdates' long-poll timeout in seconds; :interval is the
  # pause between polls, needed only to avoid a hot loop when the timeout
  # is 0.
  @config Application.compile_env(:manager, :poll,
            interval: 500,
            timeout: 30,
            limit: 100,
            retries: 10
          )

  @error_backoff_ms 1_000

  defstruct [
    :interval,
    :timer_ref,
    :update_id,
    :retries_left,
    :max_retries,
    :error
  ]

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl GenServer
  def init(_) do
    spawn(fn -> Nadia.delete_webhook() end)
    timer_ref = Process.send_after(__MODULE__, :poll, 100)
    retries = Keyword.get(@config, :retries, 10)

    state = %__MODULE__{
      interval: Keyword.get(@config, :interval, 500),
      timer_ref: timer_ref,
      retries_left: retries,
      max_retries: retries
    }

    {:ok, state}
  end

  # ignore this
  @impl GenServer
  def handle_info({:ssl_closed, _}, s), do: {:noreply, s}

  @impl GenServer
  def handle_info(:poll, %{retries_left: 0} = s) do
    {:stop, :retries_runs_out, s}
  end

  @impl GenServer
  def handle_info(:poll, s) do
    opts =
      [
        limit: Keyword.get(@config, :limit, 100),
        timeout: Keyword.get(@config, :timeout, 30),
        offset: s.update_id
      ]
      |> Enum.reject(fn {_, v} -> is_nil(v) end)

    case Nadia.get_updates(opts) do
      {:ok, updates} ->
        Manager.Updater.dispatch_updates(updates)

        timer_ref = Process.send_after(__MODULE__, :poll, s.interval)

        new_state = %{
          s
          | update_id: next_offset(updates, s.update_id),
            retries_left: s.max_retries,
            timer_ref: timer_ref,
            error: nil
        }

        {:noreply, new_state}

      {:error, err} ->
        Logger.warning("getUpdates failed (#{s.retries_left - 1} retries left): #{inspect(err)}")
        timer_ref = Process.send_after(__MODULE__, :poll, @error_backoff_ms)

        new_state = %{
          s
          | retries_left: s.retries_left - 1,
            timer_ref: timer_ref,
            error: err
        }

        {:noreply, new_state}
    end
  end

  # An empty poll must leave the offset alone; resetting it replays every
  # update telegram still holds.
  defp next_offset([], current), do: current

  defp next_offset(updates, _current) do
    highest = updates |> Enum.map(fn %{update_id: id} -> id end) |> Enum.max()
    highest + 1
  end
end
