defmodule Hexguard.OutdatedTest do
  use ExUnit.Case, async: true

  alias Hexguard.Outdated

  test "parse_table/1 parses outdated rows and ignores metadata" do
    output = """
    Dependency        Current  Latest  Status
    ash               3.14.0   3.15.0  Update possible
    phoenix           1.8.1    1.8.3   Up-to-date
    Run `mix hex.outdated APP` to show requirements
    To view the diffs, run mix hex.package diff APP
    https://hex.pm/packages/example
    """

    assert [
             %{dep: "ash", current: "3.14.0", latest: "3.15.0", status: "Update possible"},
             %{dep: "phoenix", current: "1.8.1", latest: "1.8.3", status: "Up-to-date"}
           ] = Outdated.parse_table(output)
  end

  test "parse_table/1 parses rows with dependency lock marker column" do
    output = "ash  *  3.14.0  3.15.0  Update possible"

    assert [
             %{dep: "ash", current: "3.14.0", latest: "3.15.0", status: "Update possible"}
           ] = Outdated.parse_table(output)
  end

  test "filter_update_candidates/1 keeps only update possible rows" do
    rows = [
      %{dep: "ash", status: "Update possible"},
      %{dep: "phoenix", status: "Up-to-date"}
    ]

    assert [%{dep: "ash", status: "Update possible"}] = Outdated.filter_update_candidates(rows)
  end
end
