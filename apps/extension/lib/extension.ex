defmodule Extension do
  alias Nadia.Model.{Message, InlineQuery, CallbackQuery}

  @type event :: :message | :callback | :inline_callback
  @type payload :: Message.t() | InlineQuery.t() | CallbackQuery.t()
  @type action :: :skip | :ok | :break

  @type state :: any()

  @doc """
  Called when a new event is received.
  """
  @callback on(event, payload, state) :: action | {action, state}

  @doc """
  See `GenEvent` `handle_info` callback, return type follows `handle_info`.
  """
  @callback on_info(:timeout | term(), state) :: any()
  @callback new() :: state

  defguard is_event(t) when t in [:message, :callback, :inline_callback]

  defmacro __using__(_opts) do
    quote do
      use GenServer

      import Extension, only: [is_event: 1]

      @behaviour Extension

      @impl GenServer
      def init(_) do
        case Extension.Store.load_state(__MODULE__) do
          {:ok, state} -> {:ok, state}
          :undef -> {:ok, new()}
          {:error, reason} -> {:stop, reason}
        end
      end

      def new() do
        nil
      end

      def save(s) do
        Extension.Store.save_state(__MODULE__, s)
      end

      def start_link(_) do
        GenServer.start_link(__MODULE__, nil, name: __MODULE__)
      end

      def handle({event, payload}) when is_event(event) do
        GenServer.call(__MODULE__, {event, payload})
      end

      @impl GenServer
      def handle_call({event, payload}, _s, m) when is_event(event) do
        process_event({event, payload}, m)
      end

      @impl GenServer
      def handle_info(msg, s) do
        on_info(msg, s)
      end

      def on_info(e, s) do
        {:stop, {:unhandled_info, e, s}}
      end

      defp process_event({event, payload}, s) do
        case on(event, payload, s) do
          :ok -> {:reply, :ok, s}
          :break -> {:reply, :break, s}
          {:ok, s} -> {:reply, :ok, s}
          {:break, s} -> {:reply, :break, s}
        end
      rescue
        e in [FunctionClauseError, UndefinedFunctionError] ->
          {:reply, :skip, s}
      end

      defoverridable init: 1, new: 0, on_info: 2, save: 1, handle: 1
    end
  end
end
