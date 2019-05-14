defmodule Extension do
  alias Nadia.Model.{Message, CallbackQuery}

  @type update :: Message.t() | CallbackQuery.t()
  @type state :: any()
  @type on_ret_action :: :ok | :skip | :break
  @type on_ret_t :: on_ret_action() | {on_ret_action(), state()}

  @type init_ret_t ::
          {:ok, state()}
          | {:ok, state(), timeout() | :hibernate | {:continue, term()}}
          | :ignore
          | {:stop, reason :: any()}

  @callback on(update(), state()) :: on_ret_t()
  @callback on_info(term(), state()) :: {:noreply, state()} | {:stop, term()}

  @callback before_init() :: any()
  @callback new() :: state()
  @callback from_saved(term()) :: state()
  @callback after_init(init_ret_t()) :: init_ret_t()
  @callback save(state()) :: any()

  @optional_callbacks [
    on: 2,
    on_info: 2,
    before_init: 0,
    new: 0,
    from_saved: 1,
    after_init: 1,
    save: 1
  ]

  defmacro __using__(_) do
    self = __MODULE__

    quote do
      use GenServer
      @behaviour unquote(self)

      # Callbacks for Ext
      @impl unquote(self)
      def on(update, state), do: unquote(self).DefaultAction.on(__MODULE__, update, state)
      @impl unquote(self)
      def on_info(msg, state), do: unquote(self).DefaultAction.on_info(__MODULE__, msg, state)
      @impl unquote(self)
      def new(), do: unquote(self).DefaultAction.new(__MODULE__)
      @impl unquote(self)
      def save(state), do: unquote(self).DefaultAction.save(__MODULE__, state)
      @impl unquote(self)
      def from_saved(save), do: unquote(self).DefaultAction.from_saved(__MODULE__, save)
      @impl unquote(self)
      def before_init(), do: unquote(self).DefaultAction.before_init(__MODULE__)
      @impl unquote(self)
      def after_init(state), do: unquote(self).DefaultAction.after_init(__MODULE__, state)

      defoverridable on: 2,
                     on_info: 2,
                     new: 0,
                     from_saved: 1,
                     save: 1,
                     before_init: 0,
                     after_init: 1

      def start_link(_) do
        GenServer.start_link(__MODULE__, nil, name: __MODULE__)
      end

      @impl GenServer
      def init(nil) do
        unquote(self).init(__MODULE__)
      end

      @impl GenServer
      def handle_call({:process_update, update}, from, state) do
        unquote(self).handle_process_update(__MODULE__, update, from, state)
      end

      @impl GenServer
      def handle_info(msg, state) do
        unquote(self).handle_info(__MODULE__, msg, state)
      end
    end
  end

  def init(mod) do
    mod.before_init()

    state =
      case Extension.Store.load_state(mod) do
        {:ok, state} -> {:ok, mod.from_saved(state)}
        :undef -> {:ok, mod.new()}
        {:error, reason} -> {:stop, reason}
      end

    mod.after_init(state)
  end

  @spec process_update(atom(), update()) :: :ok | :break
  def process_update(ext, payload) do
    GenServer.call(ext, {:process_update, payload})
  end

  def handle_process_update(ext, payload, from, state) do
    {reply, new_state} =
      case ext.on(payload, state) do
        {action, new_state} ->
          {action_to_reply(action), new_state}

        action ->
          {action_to_reply(action), state}
      end

    GenServer.reply(from, reply)

    ext.save(new_state)
    {:noreply, new_state}
  rescue
    e in FunctionClauseError ->
      case e do
        %{function: :on, arity: 2} -> {:reply, :ok, state}
        _ -> reraise e, __STACKTRACE__
      end
  end

  def action_to_reply(:ok), do: :ok
  def action_to_reply(:skip), do: :ok
  def action_to_reply(:break), do: :break

  def handle_info(ext, msg, state), do: ext.on_info(msg, state)

  defmodule DefaultAction do
    @moduledoc "Default actions for a extension"
    def on(_ext, _update, _state), do: :break
    def on_info(_ext, _message, state), do: {:noreply, state}
    def new(ext), do: struct!(ext, %{})
    def save(ext, state), do: Extension.Store.save_state(ext, state)
    def from_saved(_ext, save), do: save
    def before_init(_ext), do: nil
    def after_init(_ext, state), do: state
  end
end
