defmodule Hexguard.GitTest do
  use ExUnit.Case, async: true

  import Mimic

  alias Hexguard.Git
  alias Hexguard.Runner

  setup :verify_on_exit!

  test "ensure_clean_worktree/0 returns :ok for clean output" do
    expect(Runner, :run_command, fn "git", ["status", "--porcelain"], _opts -> {:ok, "\n"} end)

    assert :ok = Git.ensure_clean_worktree()
  end

  test "ensure_clean_worktree/0 returns error for dirty output" do
    expect(Runner, :run_command, fn "git", ["status", "--porcelain"], _opts ->
      {:ok, " M lib/app.ex\n"}
    end)

    assert {:error, "git worktree must be clean before running this task"} =
             Git.ensure_clean_worktree()
  end

  test "create_branch/1 runs git switch -c" do
    expect(Runner, :run_command, fn "git", ["switch", "-c", "chore/deps/ash-1.0.0"], _opts ->
      {:ok, ""}
    end)

    assert :ok = Git.create_branch("chore/deps/ash-1.0.0")
  end

  test "commit_all/1 runs add and commit" do
    expect(Runner, :run_command, 2, fn
      "git", ["add", "-A"], _opts -> {:ok, ""}
      "git", ["commit", "-m", "chore(deps): update ash from 1.0.0 to 1.1.0"], _opts -> {:ok, ""}
    end)

    assert :ok = Git.commit_all("chore(deps): update ash from 1.0.0 to 1.1.0")
  end

  test "push_origin/1 runs push command" do
    expect(Runner, :run_command, fn "git",
                                    ["push", "-u", "origin", "chore/deps/ash-1.1.0"],
                                    _opts ->
      {:ok, ""}
    end)

    assert :ok = Git.push_origin("chore/deps/ash-1.1.0")
  end
end
