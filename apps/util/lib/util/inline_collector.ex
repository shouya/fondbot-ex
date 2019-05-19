defmodule Util.InlineResultCollector do
  use GenServer

  alias Nadia.Model.InlineQueryResult

  defstruct [:timeout, :max_timeout, :collectors]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    state =
      Keyword.merge([timeout: 1000, max_timeout: 5000, collectors: %{}], opts)
      |> Map.new()

    {:ok, struct!(__MODULE__, state)}
  end

  @spec add(binary(), InlineQueryResult.t()) :: :ok
  def add(id, results) do
    GenServer.cast(__MODULE__, {:add, id, results})
  end

  @spec extend(binary(), milliseconds :: non_neg_integer()) :: :ok
  def extend(id, duration) do
    GenServer.cast(__MODULE__, {:extend, id, duration})
  end

  def handle_cast({:add, id, results}, state) do
    if Map.has_key?(state.collectors, id) do
      collectors =
        Map.update!(state.collectors, id, fn value ->
          Map.update!(value, :results, &(&1 ++ results))
        end)

      {:noreply, %{state | collectors: collectors}}
    else
      collector = %{new_collector(id, state.timeout) | results: results}
      collectors = Map.put(state.collectors, id, collector)
      {:noreply, %{state | collectors: collectors}}
    end
  end

  def handle_cast({:extend, id, duration}, %{collectors: collectors} = state) do
    case Map.get(collectors, id) do
      nil ->
        {:noreply, state}

      collector ->
        new_collector = extend_collector(collector, duration, state.max_timeout)
        collectors = Map.put(state.collectors, id, new_collector)
        {:noreply, %{state | collectors: collectors}}
    end
  end

  def hanlde_info({:flush, id}, %{collectors: collectors} = s) do
    case Map.get(collectors, id) do
      nil ->
        {:noreply, s}

      collector ->
        answer_inline_query(collector)
        {:noreply, %{s | collectors: Map.delete(collectors, id)}}
    end
  end

  defp answer_inline_query(collector) do
    Nadia.answer_inline_query(collector.id, collector.results)
  end

  defp extend_collector(%{timer: timer} = c, duration, max_timeout) do
    now = monotonic_now()
    goal = min(now + duration, c.setup_at + max_timeout)
    curr = now + Process.read_timer(timer)

    if goal > curr do
      Process.cancel_timer(timer)
      new_timer = Process.send_after(self(), {:flush, c.id}, goal - now)
      %{c | timer: new_timer}
    else
      c
    end
  end

  defp new_collector(id, timeout) do
    timer = Process.send_after(self(), {:flush, id}, timeout)

    %{
      id: id,
      setup_at: monotonic_now(),
      timer: timer,
      results: []
    }
  end

  defp monotonic_now() do
    System.monotonic_time(:millisecond)
  end
end
