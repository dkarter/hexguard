defmodule Hexguard.EvaluationTest do
  use ExUnit.Case, async: true

  alias Hexguard.Evaluation

  test "normalize/1 validates and normalizes a valid evaluation" do
    parsed = %{
      "safe" => true,
      "security_status" => "none",
      "security_concerns" => [],
      "breaking_status" => "none",
      "breaking_changes" => [],
      "compatibility" => "compatible",
      "notes" => "all good"
    }

    assert {:ok, normalized} = Evaluation.normalize(parsed)
    assert normalized["change_summary"] == "all good"
    assert normalized["notes"] == "all good"
    assert normalized["security_notes"] == ""
    assert normalized["compatibility_notes"] == ""
  end

  test "normalize/1 rejects unexpected keys" do
    parsed = %{
      "safe" => true,
      "security_status" => "none",
      "security_concerns" => [],
      "breaking_status" => "none",
      "breaking_changes" => [],
      "compatibility" => "compatible",
      "change_summary" => "summary",
      "notes" => "notes",
      "extra" => "nope"
    }

    assert {:error, reason} = Evaluation.normalize(parsed)
    assert reason =~ "unexpected keys"
  end

  test "normalize/1 rejects schema-invalid fields" do
    parsed = %{
      "safe" => true,
      "security_status" => "none",
      "security_concerns" => [],
      "breaking_status" => "none",
      "breaking_changes" => [],
      "compatibility" => "maybe",
      "change_summary" => "summary",
      "notes" => "notes"
    }

    assert {:error, reason} = Evaluation.normalize(parsed)
    assert reason =~ "did not match expected schema"
  end

  test "unsafe?/1 blocks only security-related concerns by default" do
    assert Evaluation.unsafe?(%{"safe" => false})
    assert Evaluation.unsafe?(%{"security_status" => "concern"})
    assert Evaluation.unsafe?(%{"security_status" => "unknown"})

    refute Evaluation.unsafe?(%{"breaking_status" => "concern"})
    refute Evaluation.unsafe?(%{"breaking_status" => "unknown"})
    refute Evaluation.unsafe?(%{"compatibility" => "incompatible"})
    refute Evaluation.unsafe?(%{"compatibility" => "unknown"})

    refute Evaluation.unsafe?(%{
             "safe" => true,
             "security_status" => "none",
             "breaking_status" => "none",
             "compatibility" => "compatible"
           })
  end

  test "unsafe?/2 strict mode also blocks breaking and compatibility concerns" do
    assert Evaluation.unsafe?(%{"safe" => false}, :strict)
    assert Evaluation.unsafe?(%{"security_status" => "concern"}, :strict)
    assert Evaluation.unsafe?(%{"security_status" => "unknown"}, :strict)
    assert Evaluation.unsafe?(%{"breaking_status" => "concern"}, :strict)
    assert Evaluation.unsafe?(%{"breaking_status" => "unknown"}, :strict)
    assert Evaluation.unsafe?(%{"compatibility" => "incompatible"}, :strict)
    assert Evaluation.unsafe?(%{"compatibility" => "unknown"}, :strict)
  end

  test "decode_json_from_output/1 accepts strict JSON output" do
    output =
      ~s({"safe":true,"security_status":"none","security_concerns":[],"breaking_status":"none","breaking_changes":[],"compatibility":"compatible","change_summary":"ok","notes":"ok"})

    assert {:ok, parsed} = Evaluation.decode_json_from_output(output)
    assert parsed["safe"]
  end

  test "decode_json_from_output/1 accepts fenced JSON output" do
    output = "```json\n{\"safe\":true}\n```"

    assert {:ok, parsed} = Evaluation.decode_json_from_output(output)
    assert parsed["safe"]
  end

  test "decode_json_from_output/1 rejects non-strict mixed output" do
    output = "analysis before\n{\"safe\":true}\nanalysis after"

    assert {:error, reason} = Evaluation.decode_json_from_output(output)
    assert reason =~ "could not find strict JSON"
  end

  test "extract_text_output/1 returns combined opencode text parts" do
    line1 = JSON.encode!(%{"type" => "text", "part" => %{"text" => "first"}})
    line2 = JSON.encode!(%{"type" => "step_start"})
    line3 = JSON.encode!(%{"type" => "text", "part" => %{"text" => "second"}})

    assert {:ok, "first\nsecond"} =
             Evaluation.extract_text_output(Enum.join([line1, line2, line3], "\n"))
  end

  test "extract_text_output/1 falls back to original output" do
    output = "not json lines"
    assert {:ok, ^output} = Evaluation.extract_text_output(output)
  end
end
