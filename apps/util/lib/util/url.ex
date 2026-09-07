defmodule Util.Url do
  @moduledoc """
  Checks on URLs that arrive from users, before the bot fetches them or
  offers them as a link.
  """

  import Bitwise

  @type reason :: :not_http | :no_host | :private_address | :unresolvable

  @schemes ["http", "https"]

  @spec http_link?(any()) :: boolean()
  def http_link?(text) when is_binary(text) do
    uri = URI.parse(text)
    uri.scheme in @schemes and not is_nil(uri.host) and uri.host != ""
  end

  def http_link?(_), do: false

  @doc """
  Rejects anything the bot must not fetch on a user's behalf: non-http
  schemes and hosts that resolve into the network the bot itself runs in.
  """
  @spec public_http(any()) :: {:ok, URI.t()} | {:error, reason()}
  def public_http(text) when is_binary(text) do
    uri = URI.parse(text)

    cond do
      uri.scheme not in @schemes -> {:error, :not_http}
      is_nil(uri.host) or uri.host == "" -> {:error, :no_host}
      true -> check_addresses(uri)
    end
  rescue
    _ -> {:error, :not_http}
  end

  def public_http(_), do: {:error, :not_http}

  defp check_addresses(uri) do
    case addresses(uri.host) do
      [] -> {:error, :unresolvable}
      addrs -> if Enum.all?(addrs, &public?/1), do: {:ok, uri}, else: {:error, :private_address}
    end
  end

  defp addresses(host) do
    host = String.to_charlist(host)

    case :inet.parse_address(host) do
      {:ok, addr} ->
        [addr]

      {:error, _} ->
        for family <- [:inet, :inet6],
            {:ok, addrs} <- [:inet.getaddrs(host, family)],
            addr <- addrs,
            do: addr
    end
  end

  defp public?({0, _, _, _}), do: false
  defp public?({10, _, _, _}), do: false
  defp public?({127, _, _, _}), do: false
  defp public?({169, 254, _, _}), do: false
  defp public?({192, 168, _, _}), do: false
  defp public?({172, b, _, _}) when b in 16..31, do: false
  defp public?({100, b, _, _}) when b in 64..127, do: false
  defp public?({192, 0, 0, _}), do: false
  defp public?({198, b, _, _}) when b in 18..19, do: false
  defp public?({a, _, _, _}) when a >= 224, do: false
  defp public?({_, _, _, _}), do: true

  defp public?({0, 0, 0, 0, 0, 0, 0, 0}), do: false
  defp public?({0, 0, 0, 0, 0, 0, 0, 1}), do: false

  defp public?({0, 0, 0, 0, 0, 0xFFFF, ab, cd}) do
    public?({ab >>> 8, ab &&& 0xFF, cd >>> 8, cd &&& 0xFF})
  end

  defp public?({a, _, _, _, _, _, _, _}) when (a &&& 0xFE00) == 0xFC00, do: false
  defp public?({a, _, _, _, _, _, _, _}) when (a &&& 0xFFC0) == 0xFE80, do: false
  defp public?({a, _, _, _, _, _, _, _}) when (a &&& 0xFF00) == 0xFF00, do: false
  defp public?({_, _, _, _, _, _, _, _}), do: true
end
