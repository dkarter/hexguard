defmodule Hexguard.SafetyTest do
  use ExUnit.Case, async: true

  import Mimic

  alias Hexguard.Evaluation
  alias Hexguard.Safety

  setup :verify_on_exit!

  test "ensure_safe/2 returns :ok when all assessments are safe" do
    expect(Evaluation, :unsafe?, 2, fn _assessment, _mode -> false end)

    assessments = [%{"safe" => true}, %{"safe" => true}]

    assert :ok = Safety.ensure_safe(assessments)
  end

  test "ensure_safe/2 default mode blocks with security-focused reason" do
    expect(Evaluation, :unsafe?, 2, fn assessment, mode ->
      assert mode == :security_only
      assessment == %{"id" => 2}
    end)

    assessments = [%{"id" => 1}, %{"id" => 2}]

    assert {:blocked, "security concern detected in dependency change", %{"id" => 2}} =
             Safety.ensure_safe(assessments)
  end

  test "ensure_safe/2 strict mode uses strict blocked reason" do
    expect(Evaluation, :unsafe?, 1, fn _assessment, mode ->
      assert mode == :strict
      true
    end)

    assessments = [%{"id" => 1}, %{"id" => 2}]

    assert {:blocked, "unsafe or incompatible dependency change", %{"id" => 1}} =
             Safety.ensure_safe(assessments, :strict)
  end
end
