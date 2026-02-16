defmodule Hexguard.LockfileTest do
  use ExUnit.Case, async: true

  alias Hexguard.Lockfile

  test "changes/2 returns only version deltas" do
    before_versions = %{
      "ash" => "3.14.0",
      "phoenix" => "1.8.2",
      "same" => "1.0.0",
      "removed" => "0.1.0"
    }

    after_versions = %{
      "ash" => "3.15.0",
      "phoenix" => "1.8.2",
      "same" => "1.0.0",
      "added" => "0.2.0"
    }

    assert [%{dep: "ash", from: "3.14.0", to: "3.15.0"}] =
             Lockfile.changes(before_versions, after_versions)
  end

  test "read_versions/0 returns lock versions map" do
    assert {:ok, versions} = Lockfile.read_versions()
    assert is_map(versions)
  end
end
