defmodule Manager.Updater.Poll do
  use GenServer

  @poll_config Application.get_env(:manager, :poll,
                 interval: 1,
                 limit: 100,
                 retries: 10
               )

  defstruct [
    :callback,
    :timer_ref,
    :update_id,
    :retries_left,
    :max_retries,
    :error
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init({mod, func}) do
    timer_ref = Process.send_after(__MODULE__, :poll, 100)

    state =
      %__MODULE__{}
      |> Map.put(:interval, Keyword.get(@poll_config, :interval, 1))
      |> Map.put(:callback, {mod, func})
      |> Map.put(:timer_ref, timer_ref)
      |> Map.put(:retries_left, Keyword.get(@poll_config, :retries, 10))

    {:ok, state}
  end

  # ignore this
  def handle_info({:ssl_closed, _}, s), do: s

  def handle_info(:poll, %{retries_left: 0} = s) do
    {:stop, :retries_runs_out, s}
  end

  def handle_info(:poll, %{callback: callback} = s) do
    opts =
      []
      |> Keyword.put(:limit, Keyword.get(@poll_config, :limit, 100))
      |> Keyword.put(:offset, Map.get(s, :update_id))
      |> Enum.reject(fn {_, v} -> is_nil(v) end)

    case Nadia.get_updates(opts) do
      {:ok, updates} ->
        dispatch_updates(callback, updates)

        update_id =
          updates
          |> Enum.map(fn %{update_id: id} -> id end)
          |> Enum.max(fn -> 0 end)

        timer_ref = Process.send_after(__MODULE__, :poll, Map.get(s, :interval))

        new_state =
          s
          |> Map.put(:update_id, update_id + 1)
          |> Map.put(:retries_left, Map.get(s, :max_retries))
          |> Map.put(:timer_ref, timer_ref)
          |> Map.put(:error, nil)

        {:noreply, new_state}

      {:error, err} ->
        timer_ref = Process.send_after(__MODULE__, :poll, 300)

        new_state =
          s
          |> Map.update!(:retries_left, &(&1 - 1))
          |> Map.put(:timer_ref, timer_ref)
          |> Map.put(:error, err)

        {:noreply, new_state}
    end
  end

  def dispatch_updates(_, []), do: nil

  def dispatch_updates({mod, func}, [%{message: m} | xs]) when not is_nil(m) do
    apply(mod, func, [m])
    dispatch_updates({mod, func}, xs)
  end

  def dispatch_updates({mod, func}, [%{callback_query: m} | xs]) when not is_nil(m) do
    apply(mod, func, [m])
    dispatch_updates({mod, func}, xs)
  end

  def dispatch_updates({mod, func}, [_m | xs]) do
    # unsupported message type, skipped
    dispatch_updates({mod, func}, xs)
  end
end
