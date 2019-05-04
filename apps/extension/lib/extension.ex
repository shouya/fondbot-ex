defmodule Extension do
  alias Nadia.Model.{Message, InlineQuery, CallbackQuery}

  @type payload :: Message.t() | InlineQuery.t() | CallbackQuery.t()
  @type action :: :skip | :ok | :break

  @type state :: any()

  @doc """
  Called when a new event is received.
  """
  @callback on(payload, state) :: action | {action, state}

  @doc """
  See `GenEvent` `handle_info` callback, return type follows `handle_info`.
  """
  @callback on_info(:timeout | term(), state) ::
              {:noreply, term()} | {:stop, reason :: term()}
  @callback new() :: state

  defmacro __using__(_opts) do
    quote do
      use GenServer

      @behaviour Extension

      @impl GenServer
      def init(_) do
        before_init()

        state =
          case Extension.Store.load_state(__MODULE__) do
            {:ok, state} -> {:ok, from_save(state)}
            :undef -> {:ok, new()}
            {:error, reason} -> {:stop, reason}
          end

        after_init(state)
      end

      @impl Extension
      def new() do
        nil
      end

      def from_save(x), do: x

      def save(s) do
        Extension.Store.save_state(__MODULE__, s)
      end

      def before_init(), do: nil
      def after_init(s), do: s

      def start_link(_) do
        GenServer.start_link(__MODULE__, nil, name: __MODULE__)
      end

      def process_event(payload) do
        GenServer.call(__MODULE__, {:event, payload})
      end

      @impl GenServer
      def handle_call({:event, payload}, _s, m) do
        process_event(payload, m)
      end

      @impl GenServer
      def handle_info(msg, s) do
        on_info(msg, s)
      end

      @impl Extension
      def on_info(e, s) do
        {:stop, {:unhandled_info, e, s}}
      end

      defp process_event(payload, s) do
        case on(payload, s) do
          :ok ->
            {:reply, :ok, s}

          :break ->
            {:reply, :break, s}

          {:ok, s} ->
            save(s)
            {:reply, :ok, s}

          {:break, s} ->
            save(s)
            {:reply, :break, s}
        end
      rescue
        e in [FunctionClauseError, UndefinedFunctionError] ->
          {:reply, :skip, s}
      end

      defoverridable init: 1,
                     new: 0,
                     on_info: 2,
                     save: 1,
                     process_event: 1,
                     from_save: 1,
                     before_init: 0,
                     after_init: 1
    end
  end
end
