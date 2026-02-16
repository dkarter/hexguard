defmodule HexguardTest do
  use ExUnit.Case, async: true

  test "mix task module is available" do
    assert Code.ensure_loaded?(Mix.Tasks.Hexguard)
  end
end
