defmodule Hexguard.SimulationTest do
  use ExUnit.Case, async: true

  alias Hexguard.Simulation

  test "marker_present?/2 detects marker in strings and lists" do
    evaluation = %{
      "notes" => "looks safe",
      "change_summary" => "ALBATROSS-4141 included",
      "security_concerns" => ["none"]
    }

    assert Simulation.marker_present?(evaluation, "albatross-4141")
  end

  test "marker_present?/2 ignores non-string fields" do
    evaluation = %{"safe" => true, "count" => 2, "items" => [1, 2, 3]}
    refute Simulation.marker_present?(evaluation, "albatross-4141")
  end

  test "marker_present?/2 returns false for invalid input" do
    refute Simulation.marker_present?([], "albatross-4141")
    refute Simulation.marker_present?(%{"notes" => "ok"}, :marker)
  end
end
