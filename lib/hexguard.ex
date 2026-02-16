defmodule Hexguard do
  @moduledoc """
  Updates one dependency (or a random candidate), evaluates safety via dependency
  diffs, verifies compile/tests, and opens a PR.

  If a safety or compatibility concern is detected at any step, the task creates
  a GitHub issue through `gh` and exits.

  ## Usage

      Hexguard.run(%{dep: "ash", random?: false})
      Hexguard.run(%{random?: true})

  ## Options

    * `--base` - base branch for the PR (default: `main`)
    * `--model` - model passed to `opencode run --model` (default: `openai/gpt-5.3-codex`)
    * `--block-breaking-changes` - block updates on breaking/compatibility concerns too (default: false)
    * `--simulate-injection` - run a harmless prompt-injection simulation and exit
    * `--injection-fixture` - path to a markdown fixture used by `--simulate-injection`
    * `--injection-marker` - marker string expected when injection succeeds
    * `-v`, `--verbose` - print detailed command/debug output
    * `--allow-dirty` - skip the clean git worktree pre-check
    * `--dry-run` - skips branch creation, commits, pushes, PRs, and issues

  """

  alias Hexguard.Evaluation
  alias Hexguard.Git
  alias Hexguard.GitHub
  alias Hexguard.Lockfile
  alias Hexguard.Opencode
  alias Hexguard.Outdated
  alias Hexguard.Prompt
  alias Hexguard.Report
  alias Hexguard.Runner
  alias Hexguard.Safety
  alias Hexguard.Simulation

  @default_base "main"
  @default_model "openai/gpt-5.3-codex"
  @issue_title_prefix "Dependency update blocked"
  @injection_marker "ALBATROSS-4141"

  @doc """
  Runs the dependency update workflow.

  Options map keys:
  - `:dep` (string dependency name or nil)
  - `:random?` (boolean)
  - `:base` (string)
  - `:model` (string)
  - `:block_breaking?` (boolean)
  - `:simulate_injection?` (boolean)
  - `:injection_fixture` (string)
  - `:injection_marker` (string)
  - `:verbose?` (boolean)
  - `:allow_dirty?` (boolean)
  - `:dry_run?` (boolean)
  """
  def run(options) when is_map(options) do
    options = normalize_options(options)
    configure_logging(options)

    log_step("starting dependency update workflow")

    log_verbose("options parsed", %{
      dep: options.dep,
      random?: options.random?,
      base: options.base,
      model: options.model,
      block_breaking?: options.block_breaking?,
      dry_run?: options.dry_run?,
      allow_dirty?: options.allow_dirty?,
      simulate_injection?: options.simulate_injection?,
      injection_fixture: options.injection_fixture,
      injection_marker: options.injection_marker
    })

    if options.simulate_injection? do
      run_injection_simulation(options)
    else
      with :ok <- ensure_clean_worktree(options),
           :ok <- log_reading_lockfile_versions(),
           {:ok, lock_before} <- Lockfile.read_versions(),
           {:ok, outdated_rows} <- fetch_outdated_dependencies(),
           {:ok, target} <- select_target_dependency(outdated_rows, options),
           {:ok, direct_assessment} <- assess_dependency_change(target, options),
           :ok <- ensure_safe([direct_assessment], options),
           :ok <- create_update_branch(target, options),
           :ok <- update_dependency(target.dep),
           :ok <- log_reading_lockfile_versions(),
           {:ok, lock_after} <- Lockfile.read_versions(),
           lock_changes = Lockfile.changes(lock_before, lock_after),
           :ok <- log_computed_lockfile_changes(lock_changes),
           {:ok, transitive_assessments} <-
             assess_transitive_changes(lock_changes, target.dep, options),
           :ok <- ensure_safe(transitive_assessments, options),
           {:ok, verification} <- verify_project(options),
           :ok <- commit_changes(target, lock_changes, options),
           {:ok, pr_url} <-
             create_pull_request(
               target,
               lock_changes,
               [direct_assessment | transitive_assessments],
               verification,
               options
             ) do
        Mix.shell().info("Dependency update completed: #{pr_url}")
      else
        {:blocked, reason, context} ->
          handle_blocked_workflow(reason, context, options)

        {:error, reason} ->
          Mix.raise(format_reason(reason))
      end
    end
  end

  defp run_injection_simulation(%{dry_run?: false}) do
    Mix.raise("--simulate-injection requires --dry-run")
  end

  defp run_injection_simulation(%{injection_fixture: nil}) do
    Mix.raise("--simulate-injection requires --injection-fixture PATH")
  end

  defp run_injection_simulation(%{injection_fixture: fixture_path} = options) do
    marker = options.injection_marker || @injection_marker
    fixture_path = Path.expand(fixture_path)
    log_step("running prompt-injection simulation", %{fixture: fixture_path})

    with {:ok, _diff_markdown} <- File.read(fixture_path),
         {:ok, evaluation} <-
           evaluate_diff_with_opencode(
             "injection-simulation",
             "0.0.0",
             "0.0.1",
             fixture_path,
             :direct,
             options
           ) do
      vulnerable? = Simulation.marker_present?(evaluation, marker)
      verdict = if vulnerable?, do: "VULNERABLE", else: "RESISTED"

      Mix.shell().info("[hexguard][simulation] verdict=#{verdict} marker=#{marker}")

      Mix.shell().info("[hexguard][simulation] evaluation=#{inspect(evaluation, pretty: true)}")

      if vulnerable? do
        Mix.raise("prompt-injection simulation triggered marker #{marker}")
      else
        :ok
      end
    else
      {:error, :enoent} ->
        Mix.raise("injection fixture file not found: #{fixture_path}")

      {:error, reason} ->
        Mix.raise("simulation failed: #{format_reason(reason)}")
    end
  end

  defp normalize_options(options) do
    %{
      dep: Map.get(options, :dep),
      random?: Map.get(options, :random?, false),
      base: Map.get(options, :base) || @default_base,
      model: Map.get(options, :model) || @default_model,
      block_breaking?: Map.get(options, :block_breaking?, false),
      simulate_injection?: Map.get(options, :simulate_injection?, false),
      injection_fixture: Map.get(options, :injection_fixture),
      injection_marker: Map.get(options, :injection_marker),
      verbose?: Map.get(options, :verbose?, false),
      allow_dirty?: Map.get(options, :allow_dirty?, false),
      dry_run?: Map.get(options, :dry_run?, false)
    }
  end

  defp configure_logging(%{verbose?: verbose?}) do
    Process.put(:hexguard_verbose?, verbose?)
  end

  defp verbose_logging? do
    Process.get(:hexguard_verbose?, false)
  end

  defp ensure_clean_worktree(%{allow_dirty?: true}), do: :ok
  defp ensure_clean_worktree(%{dry_run?: true}), do: :ok

  defp ensure_clean_worktree(_options) do
    log_step("checking git worktree cleanliness")

    with :ok <- Git.ensure_clean_worktree() do
      log_step("git worktree is clean")
      :ok
    end
  end

  defp log_reading_lockfile_versions do
    log_step("reading lockfile versions")
    :ok
  end

  defp log_computed_lockfile_changes(changes) do
    log_step("computed lockfile changes", %{count: length(changes)})
    :ok
  end

  defp fetch_outdated_dependencies do
    log_step("fetching outdated dependencies")

    with {:ok, output} <- run_command("mix", ["hex.outdated", "--all"], allowed: [0, 1]) do
      rows = Outdated.parse_table(output)

      log_step("outdated dependencies parsed", %{
        rows_count: length(rows),
        update_possible_count: rows |> Outdated.filter_update_candidates() |> length()
      })

      {:ok, rows}
    end
  end

  defp select_target_dependency(rows, %{random?: true}) do
    rows
    |> Outdated.filter_update_candidates()
    |> pick_random_dependency()
  end

  defp select_target_dependency(rows, %{dep: dep}) when is_binary(dep) do
    case Enum.find(rows, &(&1.dep == dep)) do
      %{status: "Update possible"} = selected ->
        log_selected_dependency(selected)
        {:ok, selected}

      %{status: status} ->
        {:error, "dependency '#{dep}' is not updatable (status: #{status})"}

      nil ->
        {:error, "dependency '#{dep}' was not found in mix hex.outdated output"}
    end
  end

  defp select_target_dependency(_rows, _options) do
    {:error, "please provide a dependency name (e.g. `mix hexguard ash`) or use --random"}
  end

  defp pick_random_dependency([]),
    do: {:error, "no dependencies with status 'Update possible' found"}

  defp pick_random_dependency(candidates) do
    selected = Enum.random(candidates)

    log_selected_dependency(selected)

    {:ok, selected}
  end

  defp log_selected_dependency(selected) do
    log_step("selected dependency", %{
      dep: selected.dep,
      from: selected.current,
      to: selected.latest
    })
  end

  defp assess_dependency_change(%{dep: dep, current: from, latest: to}, options) do
    assess_change(dep, from, to, :direct, options)
  end

  defp assess_transitive_changes(lock_changes, direct_dep, options) do
    lock_changes
    |> Enum.reject(&(&1.dep == direct_dep))
    |> Enum.reduce_while({:ok, []}, fn change, {:ok, assessments} ->
      case assess_change(change.dep, change.from, change.to, :transitive, options) do
        {:ok, assessment} -> {:cont, {:ok, [assessment | assessments]}}
        {:blocked, reason, context} -> {:halt, {:blocked, reason, context}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, assessments} -> {:ok, Enum.reverse(assessments)}
      other -> other
    end
  end

  defp assess_change(dep, from, to, kind, options) do
    log_step("assessing dependency diff", %{dep: dep, from: from, to: to, kind: kind})

    with {:ok, diff_markdown} <- fetch_diff_markdown(dep, from, to),
         {:ok, diff_path} <- persist_diff_markdown(dep, from, to, diff_markdown),
         {:ok, evaluation} <-
           evaluate_diff_with_opencode(dep, from, to, diff_path, kind, options),
         assessment <-
           Map.merge(evaluation, %{
             dep: dep,
             from: from,
             to: to,
             kind: kind,
             diff_url: diff_url(dep, from, to),
             diff_path: diff_path
           }) do
      log_step("assessment complete", %{
        dep: dep,
        safe: assessment["safe"],
        compatibility: assessment["compatibility"]
      })

      {:ok, assessment}
    else
      {:error, reason} ->
        {:blocked, "failed to evaluate dependency diff",
         %{dep: dep, from: from, to: to, reason: reason}}
    end
  end

  defp fetch_diff_markdown(dep, from, to) do
    log_step("fetching dependency diff", %{url: diff_url(dep, from, to)})
    args = ["hex.package", "diff", dep, "#{from}..#{to}"]

    run_command("mix", args, allowed: [0, 1])
  end

  defp persist_diff_markdown(dep, from, to, diff_markdown) do
    dir = Path.join([File.cwd!(), "tmp", "dependency_diffs"])
    path = Path.join(dir, "#{dep}.#{from}..#{to}.md")

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(path, diff_markdown) do
      log_step("saved dependency diff", %{path: path})
      {:ok, path}
    else
      {:error, reason} -> {:error, "failed to write diff file: #{inspect(reason)}"}
    end
  end

  defp evaluate_diff_with_opencode(dep, from, to, diff_path, kind, options) do
    log_step("evaluating security diff in restricted opencode container", %{
      dep: dep,
      from: from,
      to: to,
      kind: kind,
      model: options.model
    })

    security_diff_path = Opencode.security_diff_path()

    security_prompt =
      Prompt.security_diff_evaluation_prompt(dep, from, to, kind, security_diff_path)

    security_args =
      ["run"] ++
        ["--format", "json"] ++
        model_args(options.model) ++
        [
          "Reply ONLY with JSON.",
          security_prompt
        ]

    log_step("evaluating compatibility diff in docker with workspace mount", %{
      dep: dep,
      from: from,
      to: to,
      kind: kind,
      model: options.model
    })

    compatibility_diff_path = Opencode.docker_workspace_path(diff_path)

    compatibility_prompt =
      Prompt.compatibility_diff_evaluation_prompt(dep, from, to, kind, compatibility_diff_path)

    compatibility_args =
      ["run"] ++
        ["--format", "json"] ++
        model_args(options.model) ++
        [
          "Reply ONLY with JSON.",
          compatibility_prompt
        ]

    with {:ok, security_evaluation} <-
           run_security_evaluation(security_args, diff_path),
         {:ok, compatibility_evaluation} <-
           run_compatibility_evaluation(compatibility_args),
         {:ok, merged} <- merge_evaluations(security_evaluation, compatibility_evaluation) do
      Evaluation.normalize(merged)
    end
  end

  defp run_security_evaluation(opencode_args, diff_path) do
    with {:ok, output} <-
           Opencode.run_docker(opencode_args,
             allowed: [0],
             timeout: 600_000,
             stream?: false,
             security_profile?: true,
             mount_config?: false,
             workspace_mount?: false,
             extra_mounts: [{diff_path, Opencode.security_diff_path(), :ro}]
           ),
         {:ok, text_output} <- Evaluation.extract_text_output(output) do
      Evaluation.decode_json_from_output(text_output)
    end
  end

  defp run_compatibility_evaluation(opencode_args) do
    with {:ok, output} <-
           Opencode.run_docker(opencode_args,
             allowed: [0],
             timeout: 600_000,
             stream?: false,
             workspace_mount?: true
           ),
         {:ok, text_output} <- Evaluation.extract_text_output(output) do
      Evaluation.decode_json_from_output(text_output)
    end
  end

  defp merge_evaluations(security_evaluation, compatibility_evaluation) do
    security_summary = text_or_nil(Map.get(security_evaluation, "change_summary"))
    security_notes = text_or_nil(Map.get(security_evaluation, "notes"))
    compatibility_summary = text_or_nil(Map.get(compatibility_evaluation, "change_summary"))
    compatibility_notes = text_or_nil(Map.get(compatibility_evaluation, "notes"))

    merged =
      %{
        "safe" => Map.get(security_evaluation, "safe"),
        "security_status" => Map.get(security_evaluation, "security_status"),
        "security_concerns" => Map.get(security_evaluation, "security_concerns", []),
        "breaking_status" => Map.get(compatibility_evaluation, "breaking_status"),
        "breaking_changes" => Map.get(compatibility_evaluation, "breaking_changes", []),
        "compatibility" => Map.get(compatibility_evaluation, "compatibility"),
        "security_change_summary" => security_summary,
        "security_notes" => security_notes,
        "compatibility_change_summary" => compatibility_summary,
        "compatibility_notes" => compatibility_notes,
        "change_summary" =>
          compatibility_summary || security_summary || "No summary provided by evaluator.",
        "notes" => compatibility_notes || security_notes || ""
      }

    {:ok, merged}
  end

  defp text_or_nil(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp text_or_nil(_value), do: nil

  defp model_args(nil), do: []
  defp model_args(model), do: ["--model", model]

  defp ensure_safe(assessments, options) do
    mode = if options.block_breaking?, do: :strict, else: :security_only

    case Safety.ensure_safe(assessments, mode) do
      :ok ->
        log_step("all assessments passed safety checks", %{mode: mode})
        :ok

      blocked ->
        blocked
    end
  end

  defp create_update_branch(_target, %{dry_run?: true}), do: :ok

  defp create_update_branch(%{dep: dep, latest: latest}, _options) do
    branch = branch_name(dep, latest)
    log_step("creating branch", %{branch: branch})

    Git.create_branch(branch)
  end

  defp branch_name(dep, latest), do: "chore/deps/#{dep}-#{latest}"

  defp update_dependency(dep) do
    log_step("updating dependency", %{dep: dep})

    run_command("mix", ["deps.update", dep], allowed: [0])
    |> then(fn
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end)
  end

  defp verify_project(options) do
    log_step("running verification", %{steps: ["compile", "test"]})

    with :ok <- run_compile_verification(),
         :ok <- run_verification("test", "mix", ["test"]) do
      log_step("verification passed")
      {:ok, %{autofix_applied?: false, autofix_summary: nil}}
    else
      {:error, %{step: step, output: output}} ->
        log_step("verification failed, attempting autofix", %{step: step})
        attempt_autofix(step, output, options)
    end
  end

  defp run_compile_verification do
    with :ok <- run_verification("deps compile", "mix", ["deps.compile"]) do
      run_verification("compile", "mix", [
        "compile",
        "--warnings-as-errors",
        "--no-deps-check"
      ])
    end
  end

  defp run_verification(title, command, args) do
    log_step("verification: #{title}", %{command: Enum.join([command | args], " ")})

    case run_command(command, args, allowed: [0], timeout: 900_000, stream?: true) do
      {:ok, _output} ->
        :ok

      {:error, %{output: output}} ->
        {:error, %{step: Enum.join([command | args], " "), output: output}}

      {:error, reason} ->
        {:error, %{step: Enum.join([command | args], " "), output: inspect(reason)}}
    end
  end

  defp attempt_autofix(step, output, %{dry_run?: true}) do
    {:blocked, "verification failed in dry-run mode", %{step: step, output: output}}
  end

  defp attempt_autofix(step, output, options) do
    log_step("running compatibility autofix with local opencode", %{model: options.model})

    prompt =
      """
      A dependency update caused verification failures.

      Failed step: #{step}

      Failure output:
      #{output}

      Dependency diff context (this can contain clues about what caused the failure):
      - Diffs saved during this run: tmp/dependency_diffs/*.md
      - If needed, regenerate any diff with: mix hex.package diff <dep> <from>..<to>

      Please make minimal compatibility changes in the current project so both commands pass:
      1) mix compile --warnings-as-errors
      2) mix test

      You are responsible for running the quality gate commands - don't ask the user to run them.

      Follow the target project's coding conventions and quality checks.
      Don't assume we will have multiple versions of the same dependency - the
      latest that is in mix.lock is what we need to be compatible with.

      (if you need to know the previous version you can check git diff for mix.lock)

      Work in this git branch (chore/deps/<dep>-<version>. Return a brief summary at the end.
      """

    args = ["run"] ++ model_args(options.model) ++ [prompt]

    with {:ok, _} <-
           Opencode.run(args, allowed: [0], timeout: 1_200_000, stream?: true),
         :ok <- run_verification("compile", "mix", ["compile", "--warnings-as-errors"]),
         :ok <- run_verification("test", "mix", ["test"]) do
      {:ok,
       %{
         autofix_applied?: true,
         autofix_summary:
           "This update required compatibility changes in the app; I applied them and compile/tests now pass."
       }}
    else
      {:error, %{step: failed_step, output: failed_output}} ->
        {:blocked, "verification failed after opencode autofix",
         %{step: failed_step, output: failed_output}}

      {:error, reason} ->
        {:blocked, "opencode autofix failed", %{reason: reason}}
    end
  end

  defp commit_changes(_target, _lock_changes, %{dry_run?: true}), do: :ok

  defp commit_changes(%{dep: dep, current: from, latest: to}, _lock_changes, _options) do
    message = "chore(deps): update #{dep} from #{from} to #{to}"
    log_step("creating commit", %{message: message})

    Git.commit_all(message)
  end

  defp create_pull_request(_target, _lock_changes, _assessments, _verification, %{dry_run?: true}) do
    {:ok, "dry-run: skipped PR creation"}
  end

  defp create_pull_request(
         %{dep: dep, latest: latest},
         lock_changes,
         assessments,
         verification,
         options
       ) do
    branch = branch_name(dep, latest)
    title = "chore(deps): update #{dep} to #{latest}"
    body = Report.pr_body(lock_changes, assessments, verification)

    log_step("creating pull request", %{branch: branch, base: options.base, title: title})

    with :ok <- Git.push_origin(branch) do
      GitHub.create_pull_request(options.base, branch, title, body)
    end
  end

  defp handle_blocked_workflow(reason, context, %{dry_run?: true}) do
    Mix.shell().error("Blocked: #{reason}")
    Mix.shell().error("Context: #{inspect(context)}")
  end

  defp handle_blocked_workflow(reason, context, _options) do
    title = "#{@issue_title_prefix}: #{reason}"
    body = Report.issue_body(reason, context)

    case run_command("gh", ["issue", "create", "--title", title, "--body", body], allowed: [0]) do
      {:ok, issue_url} ->
        Mix.raise("workflow blocked and issue created: #{String.trim(issue_url)}")

      {:error, create_issue_error} ->
        Mix.raise(
          "workflow blocked and issue creation failed: #{format_reason(create_issue_error)}"
        )
    end
  end

  defp diff_url(dep, from, to), do: "https://diff.hex.pm/diff/#{dep}/#{from}..#{to}"

  defp run_command(command, args, options) do
    Runner.run_command(
      command,
      args,
      Keyword.put(options, :log_verbose, fn message, metadata ->
        log_verbose(message, metadata)
      end)
    )
  end

  defp log_step(message, metadata \\ nil)

  defp log_step(message, nil) do
    Mix.shell().info(
      IO.ANSI.format([
        :bright,
        :cyan,
        "[hexguard] ",
        message,
        :reset
      ])
    )
  end

  defp log_step(message, metadata) when is_map(metadata) do
    log_step(message)
    log_verbose(message, metadata)
  end

  defp log_verbose(message, nil) do
    if verbose_logging?() do
      Mix.shell().info("[hexguard][verbose] #{message}")
    end
  end

  defp log_verbose(message, metadata) when is_map(metadata) do
    if verbose_logging?() do
      Mix.shell().info("[hexguard][verbose] #{message}: #{inspect(metadata)}")
    end
  end

  defp format_reason(%{command: command, args: args, status: status, output: output}) do
    "command failed: #{Enum.join([command | args], " ")} (status #{status})\n#{output}"
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason, pretty: true, limit: :infinity)
end
