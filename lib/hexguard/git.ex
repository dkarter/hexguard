defmodule Hexguard.Git do
  @moduledoc false

  alias Hexguard.Runner

  def ensure_clean_worktree do
    with {:ok, output} <- Runner.run_command("git", ["status", "--porcelain"], allowed: [0]) do
      if String.trim(output) == "" do
        :ok
      else
        {:error, "git worktree must be clean before running this task"}
      end
    end
  end

  def create_branch(branch) when is_binary(branch) do
    case Runner.run_command("git", ["switch", "-c", branch], allowed: [0]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def commit_all(message) when is_binary(message) do
    with {:ok, _} <- Runner.run_command("git", ["add", "-A"], allowed: [0]),
         {:ok, _} <- Runner.run_command("git", ["commit", "-m", message], allowed: [0]) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def push_origin(branch) when is_binary(branch) do
    case Runner.run_command("git", ["push", "-u", "origin", branch],
           allowed: [0],
           timeout: 600_000
         ) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
