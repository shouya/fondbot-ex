defmodule ExtensionTest do
  use ExUnit.Case
  doctest Extension

  test "greets the world" do
    assert Extension.hello() == :world
  end
end
