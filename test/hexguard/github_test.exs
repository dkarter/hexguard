defmodule Hexguard.GitHubTest do
  use ExUnit.Case, async: true

  import Mimic

  alias Hexguard.GitHub
  alias Hexguard.Runner

  setup :verify_on_exit!

  test "create_pull_request/4 runs gh pr create and trims output" do
    expect(Runner, :run_command, fn
      "gh",
      [
        "pr",
        "create",
        "--base",
        "main",
        "--head",
        "chore/deps/ash-1.1.0",
        "--title",
        "chore(deps): update ash to 1.1.0",
        "--body",
        "body"
      ],
      _opts ->
        {:ok, "https://github.com/example/repo/pull/123\n"}
    end)

    assert {:ok, "https://github.com/example/repo/pull/123"} =
             GitHub.create_pull_request(
               "main",
               "chore/deps/ash-1.1.0",
               "chore(deps): update ash to 1.1.0",
               "body"
             )
  end
end
