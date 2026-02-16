defmodule Mix.Tasks.Hexguard do
  @moduledoc """
  Updates one dependency with AI-assisted diff review and opens a PR.

  By default, provide a dependency name:

      mix hexguard ash

  Or choose a random updatable dependency:

      mix hexguard --random

  ## Options

    * `--random` - pick one random dependency with status `Update possible`
    * `--base` - base branch for the PR (default: `main`)
    * `--model` - model passed to `opencode run --model` (default: `openai/gpt-5.3-codex`)
    * `--block-breaking-changes` - also block on breaking/compatibility concerns (default: false)
    * `--simulate-injection` - run a harmless prompt-injection simulation and exit
    * `--injection-fixture` - path to a markdown fixture used by `--simulate-injection`
    * `--injection-marker` - marker string expected when injection succeeds
    * `-v`, `--verbose` - print detailed command/debug output
    * `--allow-dirty` - skip the clean git worktree pre-check
    * `--dry-run` - skips branch creation, commits, pushes, PRs, and issues
  """

  use Mix.Task

  @shortdoc "Updates a dependency and opens a PR"

  @impl Mix.Task
  def run(args) do
    options = parse_args(args)
    validate_options!(options)
    Hexguard.run(options)
  end

  defp parse_args(args) do
    {parsed, positional, _invalid} =
      OptionParser.parse(args,
        strict: [
          random: :boolean,
          base: :string,
          model: :string,
          block_breaking_changes: :boolean,
          simulate_injection: :boolean,
          injection_fixture: :string,
          injection_marker: :string,
          verbose: :boolean,
          allow_dirty: :boolean,
          dry_run: :boolean
        ],
        aliases: [b: :base, v: :verbose]
      )

    %{
      dep: parse_dep!(positional),
      random?: Keyword.get(parsed, :random, false),
      base: Keyword.get(parsed, :base),
      model: Keyword.get(parsed, :model),
      block_breaking?: Keyword.get(parsed, :block_breaking_changes, false),
      simulate_injection?: Keyword.get(parsed, :simulate_injection, false),
      injection_fixture: Keyword.get(parsed, :injection_fixture),
      injection_marker: Keyword.get(parsed, :injection_marker),
      verbose?: Keyword.get(parsed, :verbose, false),
      allow_dirty?: Keyword.get(parsed, :allow_dirty, false),
      dry_run?: Keyword.get(parsed, :dry_run, false)
    }
  end

  defp parse_dep!([dep]), do: dep
  defp parse_dep!([]), do: nil

  defp parse_dep!(_many) do
    Mix.raise("expected at most one dependency name, e.g. `mix hexguard ash`")
  end

  defp validate_options!(%{dep: dep, random?: true}) when is_binary(dep) do
    Mix.raise("use either a dependency argument or --random, not both")
  end

  defp validate_options!(_options), do: :ok
end
