defmodule Util.Telegram do
  alias Nadia.Model.User

  @spec user_name(Nadia.Model.User.t()) :: bitstring()
  def user_name(%User{first_name: first, last_name: last, username: name}) do
    first || last || name || "unnamed"
  end
end
