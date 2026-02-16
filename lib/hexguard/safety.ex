defmodule Hexguard.Safety do
  @moduledoc false

  alias Hexguard.Evaluation

  def ensure_safe(assessments, mode \\ :security_only) when is_list(assessments) do
    case Enum.find(assessments, &Evaluation.unsafe?(&1, mode)) do
      nil -> :ok
      assessment -> {:blocked, blocked_reason(mode), assessment}
    end
  end

  defp blocked_reason(:strict), do: "unsafe or incompatible dependency change"
  defp blocked_reason(_mode), do: "security concern detected in dependency change"
end
