defmodule Hexguard.ReportTest do
  use ExUnit.Case, async: true

  alias Hexguard.Report

  test "pr_body/3 renders dependency summary sections" do
    lock_changes = [%{dep: "ash", from: "3.14.0", to: "3.15.0"}]

    assessments = [
      %{
        :dep => "ash",
        :from => "3.14.0",
        :to => "3.15.0",
        :diff_url => "https://diff.hex.pm/diff/ash/3.14.0..3.15.0",
        "change_summary" => "No breaking changes.",
        "security_status" => "none",
        "security_concerns" => [],
        "breaking_status" => "none",
        "breaking_changes" => [],
        "compatibility" => "compatible"
      }
    ]

    body = Report.pr_body(lock_changes, assessments, %{autofix_applied?: false})

    assert body =~ "## Dependency Changes"
    assert body =~ "- ash: 3.14.0 -> 3.15.0"
    assert body =~ "## Review Checks"
    assert body =~ "## Review Notes"
    assert body =~ "✅ **Security**"
    assert body =~ "## Diff Links"
  end

  test "issue_body/2 renders reason and context" do
    body =
      Report.issue_body("unsafe or incompatible dependency change", %{dep: "ash", safe: false})

    assert body =~ "## Dependency update blocked"
    assert body =~ "Reason: unsafe or incompatible dependency change"
    assert body =~ "dep: \"ash\""
  end
end
