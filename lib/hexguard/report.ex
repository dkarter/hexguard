defmodule Hexguard.Report do
  @moduledoc false

  def pr_body(lock_changes, assessments, verification) do
    diff_links =
      Enum.map_join(assessments, "\n", fn assessment ->
        "- #{assessment.dep} #{assessment.from} -> #{assessment.to}: #{assessment.diff_url}"
      end)

    summaries =
      Enum.map_join(assessments, "\n", fn assessment ->
        "- #{assessment.dep} #{assessment.from} -> #{assessment.to}: #{Map.get(assessment, "change_summary")}"
      end)

    checks =
      Enum.map_join(assessments, "\n\n", fn assessment ->
        [
          "- **#{assessment.dep} #{assessment.from} -> #{assessment.to}**",
          security_check_line(assessment),
          compatibility_check_line(assessment),
          breaking_check_line(assessment)
        ]
        |> Enum.join("\n")
      end)

    review_notes =
      Enum.map_join(assessments, "\n\n", fn assessment ->
        [
          "- **#{assessment.dep} #{assessment.from} -> #{assessment.to}**",
          "  - Security summary: #{value_or_na(Map.get(assessment, "security_change_summary"))}",
          "  - Security notes: #{value_or_na(Map.get(assessment, "security_notes"))}",
          "  - Compatibility summary: #{value_or_na(Map.get(assessment, "compatibility_change_summary"))}",
          "  - Compatibility notes: #{value_or_na(Map.get(assessment, "compatibility_notes"))}"
        ]
        |> Enum.join("\n")
      end)

    changed =
      Enum.map_join(lock_changes, "\n", fn change ->
        "- #{change.dep}: #{change.from} -> #{change.to}"
      end)

    verification_line = verification_check_line(verification)

    """
    > 🤖 **AI-assisted dependency update**: this PR was created by Evergreen AI's
    > `mix hexguard` task, which performs an automated review of the
    > dependency diff to identify potential security concerns, breaking changes,
    > and compatibility risks. It makes a best effort attempt to automatically
    > fix compatibility issues when possible, but still, like with any AI code
    > changes requires human review to confirm the safety of the update and
    > verify that the changes look reasonable.

    ## Dependency Changes
    #{changed}

    ## Diff Summaries
    #{summaries}

    ## Review Checks
    #{checks}

    ## Review Notes
    #{review_notes}

    ## Verification
    #{verification_line}

    ## Diff Links
    #{diff_links}

    ## Checks Performed
    - Evaluated direct dependency diff using OpenCode for security, breaking changes, and compatibility notes
    - Verified compile is free from warnings and test suite passes after update
    - Evaluated direct and transitive dependency diffs with OpenCode
    """
  end

  def issue_body(reason, context) do
    """
    ## Dependency update blocked

    Reason: #{reason}

    ## Context
    ```elixir
    #{inspect(context, pretty: true, limit: :infinity)}
    ```
    """
  end

  defp security_check_line(assessment) do
    case assessment["security_status"] do
      "none" ->
        "  - ✅ **Security**: no security concerns identified from the package diff."

      "unknown" ->
        "  - 👀 **Security**: security risk could not be fully determined from the diff alone."

      _ ->
        "  - ⚠️ **Security**: #{first_comment(Map.get(assessment, "security_concerns"), "security concerns identified from the package diff")}"
    end
  end

  defp compatibility_check_line(assessment) do
    case assessment["compatibility"] do
      "compatible" ->
        "  - ✅ **Compatibility**: this update appears compatible with this app based on diff review."

      "unknown" ->
        "  - ⚠️ **Compatibility**: compatibility could not be fully confirmed from the diff alone."

      "incompatible" ->
        "  - ⚠️ **Compatibility**: incompatible based on diff review."

      _ ->
        "  - ⚠️ **Compatibility**: compatibility could not be fully confirmed from the diff alone."
    end
  end

  defp breaking_check_line(assessment) do
    case assessment["breaking_status"] do
      "none" ->
        "  - ✅ **Breaking changes**: no breaking changes identified from the package diff."

      "unknown" ->
        "  - 👀 **Breaking changes**: breaking-change risk could not be fully determined from the diff alone."

      _ ->
        "  - ⚠️ **Breaking changes**: #{first_comment(Map.get(assessment, "breaking_changes"), "breaking changes identified from the package diff")}"
    end
  end

  defp first_comment([first | _], _fallback) when is_binary(first), do: first
  defp first_comment(_comments, fallback), do: fallback

  defp value_or_na(value) when is_binary(value) do
    case String.trim(value) do
      "" -> "n/a"
      trimmed -> trimmed
    end
  end

  defp value_or_na(_value), do: "n/a"

  defp verification_check_line(%{autofix_applied?: true, autofix_summary: summary}) do
    "- ⚠️ **Compatibility updates**: #{summary}"
  end

  defp verification_check_line(_verification) do
    "- ✅ **Compatibility updates**: no app code changes were required; compile/tests passed."
  end
end
