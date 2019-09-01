defmodule Extension do
  alias Nadia.Model.{Message, CallbackQuery, InlineQuery}

  @type update :: Message.t() | CallbackQuery.t() | InlineQuery.t()
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

  defp impl_callback(preset, {func, loc, args} = call) do
    self = __MODULE__
    new_args = [Macro.escape(preset), Macro.escape(__MODULE__)] ++ args
    new_call = {func, loc, new_args}

    quote do
      @impl unquote(self)
      def unquote(call), do: unquote(self).DefaultAction.unquote(new_call)
    end
  end

  defmacro impl_genserver_boilerplate() do
    self = __MODULE__

    quote do
      use GenServer

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

  defmacro __using__(opts) do
    self = __MODULE__
    preset = Keyword.get(opts, :preset, :default)

    quote do
      @behaviour unquote(self)

      # Callbacks for Ext
      unquote(impl_callback(preset, quote(do: on(update, state))))
      unquote(impl_callback(preset, quote(do: on(update, state))))
      unquote(impl_callback(preset, quote(do: on_info(msg, state))))
      unquote(impl_callback(preset, quote(do: new())))
      unquote(impl_callback(preset, quote(do: save(state))))
      unquote(impl_callback(preset, quote(do: from_saved(save))))
      unquote(impl_callback(preset, quote(do: before_init())))
      unquote(impl_callback(preset, quote(do: after_init(state))))

      defoverridable on: 2,
                     on_info: 2,
                     new: 0,
                     from_saved: 1,
                     save: 1,
                     before_init: 0,
                     after_init: 1

      unquote(self).impl_genserver_boilerplate()
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
    def on(_ext, _preset, _update, _state), do: :break
    def on_info(_ext, _preset, _msg, state), do: {:noreply, state}
    def new(_ext, _preset), do: nil
    def save(ext, _preset, state), do: Extension.Store.save_state(ext, state)
    def from_saved(_ext, _preset, save), do: save
    def before_init(_ext, _preset), do: nil
    def after_init(_ext, _preset, state), do: state
  end
end
