defmodule Manager.Updater do
  alias Nadia.Model.{Message, CallbackQuery}

  @type update_t :: Message.t() | CallbackQuery.t()

  @spec dispatch_updates([update_t()]) :: nil
  def dispatch_updates([]), do: nil

  def dispatch_updates([%{message: m} | xs]) when not is_nil(m) do
    Manager.ExtStack.process_event(m)
    dispatch_updates(xs)
  end

  def dispatch_updates([%{callback_query: m} | xs]) when not is_nil(m) do
    Manager.ExtStack.process_event(m)
    dispatch_updates(xs)
  end

  def dispatch_updates([%{inline_query: m} | xs]) when not is_nil(m) do
    IO.inspect(m)
    Manager.ExtStack.process_event(m)
    dispatch_updates(xs)
  end

  def dispatch_updates([_m | xs]) do
    # unsupported message type, skipped
    dispatch_updates(xs)
  end
end
