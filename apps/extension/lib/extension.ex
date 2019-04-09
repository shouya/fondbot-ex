defmodule Extension do
  alias Nadia.Model.{Message, InlineQuery, CallbackQuery}

  @type event :: :message | :callback | :inline_callback
  @type payload :: Message.t() | InlineQuery.t() | CallbackQuery.t()
  @type action :: :skip | :ok | :break

  @type state :: any()

  @callback on(event, payload) :: action
  @callback load_state(state) :: :ok | {:error, any()}
  @callback state() :: state

  defmacro __using__(_opts) do
    quote do
      @behaviour Extension

      def init(opts) do
        {:ok, state} <- Extension.load_state(__MODULE__)
        {:ok, state}
      end

      def on(event, message) do
        GenServer.call(__MODULE__, {event, request})
      end

      defoverridable on: 2
    end
  end
end
