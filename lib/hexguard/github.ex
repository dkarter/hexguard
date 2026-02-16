defmodule Hexguard.GitHub do
  @moduledoc false

  alias Hexguard.Runner

  def create_pull_request(base, head, title, body)
      when is_binary(base) and is_binary(head) and is_binary(title) and is_binary(body) do
    with {:ok, pr_url} <-
           Runner.run_command(
             "gh",
             [
               "pr",
               "create",
               "--base",
               base,
               "--head",
               head,
               "--title",
               title,
               "--body",
               body
             ],
             allowed: [0]
           ) do
      {:ok, String.trim(pr_url)}
    end
  end
end
