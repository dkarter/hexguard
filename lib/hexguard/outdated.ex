defmodule Hexguard.Outdated do
  @moduledoc false

  def parse_table(output) when is_binary(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reject(&metadata_line?/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_row/1)
    |> Enum.reject(&is_nil/1)
  end

  def filter_update_candidates(rows) when is_list(rows) do
    Enum.filter(rows, &(&1.status == "Update possible"))
  end

  defp metadata_line?(line) do
    String.starts_with?(line, "Dependency") or
      String.starts_with?(line, "Run `mix hex.outdated") or
      String.starts_with?(line, "To view the diffs") or
      String.starts_with?(line, "https://")
  end

  defp parse_row(row) do
    case Regex.split(~r/\s{2,}/, row, trim: true) do
      [dep, current, latest, status] ->
        %{dep: dep, current: current, latest: latest, status: status}

      [dep, _only, current, latest, status] ->
        %{dep: dep, current: current, latest: latest, status: status}

      _ ->
        nil
    end
  end
end
