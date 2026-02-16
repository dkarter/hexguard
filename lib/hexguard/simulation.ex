defmodule Hexguard.Simulation do
  @moduledoc false

  def marker_present?(evaluation, marker) when is_map(evaluation) and is_binary(marker) do
    marker = String.downcase(marker)

    evaluation
    |> Map.values()
    |> Enum.flat_map(fn
      value when is_binary(value) -> [value]
      value when is_list(value) -> Enum.filter(value, &is_binary/1)
      _value -> []
    end)
    |> Enum.any?(fn value -> String.contains?(String.downcase(value), marker) end)
  end

  def marker_present?(_evaluation, _marker), do: false
end
