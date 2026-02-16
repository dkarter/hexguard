defmodule Hexguard.Evaluation do
  @moduledoc false

  import Zoi

  @allowed_keys [
    "safe",
    "security_status",
    "security_concerns",
    "breaking_status",
    "breaking_changes",
    "compatibility",
    "security_change_summary",
    "security_notes",
    "compatibility_change_summary",
    "compatibility_notes",
    "change_summary",
    "notes"
  ]

  @blocking_security_statuses ["concern", "unknown"]
  @blocking_breaking_statuses ["concern", "unknown"]

  def normalize(parsed) do
    with :ok <- ensure_allowed_keys(parsed),
         {:ok, validated} <-
           Zoi.parse(evaluation_schema(), evaluation_payload(parsed), coerce: true) do
      {:ok, evaluation_result(validated)}
    else
      {:error, errors} when is_list(errors) ->
        {:error,
         "opencode output did not match expected schema: #{inspect(Zoi.treefy_errors(errors))}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def unsafe?(assessment), do: unsafe?(assessment, :security_only)

  def unsafe?(%{"safe" => false}, _mode), do: true

  def unsafe?(%{"security_status" => status}, _mode) when status in @blocking_security_statuses,
    do: true

  def unsafe?(%{"breaking_status" => status}, :strict) when status in @blocking_breaking_statuses,
    do: true

  def unsafe?(%{"compatibility" => "incompatible"}, :strict), do: true
  def unsafe?(%{"compatibility" => "unknown"}, :strict), do: true

  def unsafe?(_assessment, _mode), do: false

  def extract_text_output(output) do
    text =
      output
      |> String.split("\n", trim: true)
      |> Enum.reduce([], fn line, acc ->
        case JSON.decode(line) do
          {:ok, %{"type" => "text", "part" => %{"text" => text_part}}}
          when is_binary(text_part) ->
            [text_part | acc]

          _ ->
            acc
        end
      end)
      |> Enum.reverse()
      |> Enum.join("\n")

    if text == "" do
      {:ok, output}
    else
      {:ok, text}
    end
  end

  def decode_json_from_output(output) do
    with {:ok, json_text} <- extract_json_text(output),
         {:ok, parsed} <- JSON.decode(json_text) do
      {:ok, parsed}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_allowed_keys(parsed) when is_map(parsed) do
    unknown_keys = Map.keys(parsed) -- @allowed_keys

    if unknown_keys == [] do
      :ok
    else
      {:error, "opencode output included unexpected keys: #{Enum.join(unknown_keys, ", ")}"}
    end
  end

  defp ensure_allowed_keys(_parsed),
    do: {:error, "opencode output did not decode to a JSON object"}

  defp evaluation_schema do
    object(
      %{
        safe: boolean(),
        security_status: enum(["none", "concern", "unknown"]),
        security_concerns: list(string()),
        breaking_status: enum(["none", "concern", "unknown"]),
        breaking_changes: list(string()),
        compatibility: enum(["compatible", "incompatible", "unknown"]),
        security_change_summary: string(),
        security_notes: string(),
        compatibility_change_summary: string(),
        compatibility_notes: string(),
        change_summary: string(min_length: 1),
        notes: string()
      },
      unrecognized_keys: :error,
      coerce: true
    )
  end

  defp evaluation_payload(parsed) do
    %{
      safe: Map.get(parsed, "safe"),
      security_status: Map.get(parsed, "security_status"),
      security_concerns: Map.get(parsed, "security_concerns"),
      breaking_status: Map.get(parsed, "breaking_status"),
      breaking_changes: Map.get(parsed, "breaking_changes"),
      compatibility: Map.get(parsed, "compatibility"),
      security_change_summary: Map.get(parsed, "security_change_summary", ""),
      security_notes: Map.get(parsed, "security_notes", ""),
      compatibility_change_summary: Map.get(parsed, "compatibility_change_summary", ""),
      compatibility_notes: Map.get(parsed, "compatibility_notes", ""),
      change_summary:
        Map.get(parsed, "change_summary") || Map.get(parsed, "notes") ||
          "No summary provided by evaluator.",
      notes: Map.get(parsed, "notes", "")
    }
  end

  defp evaluation_result(validated) do
    %{
      "safe" => validated.safe,
      "security_status" => validated.security_status,
      "security_concerns" => validated.security_concerns,
      "breaking_status" => validated.breaking_status,
      "breaking_changes" => validated.breaking_changes,
      "compatibility" => validated.compatibility,
      "security_change_summary" => validated.security_change_summary,
      "security_notes" => validated.security_notes,
      "compatibility_change_summary" => validated.compatibility_change_summary,
      "compatibility_notes" => validated.compatibility_notes,
      "change_summary" => validated.change_summary,
      "notes" => validated.notes
    }
  end

  defp extract_json_text(output) do
    trimmed_output = String.trim(output)

    case JSON.decode(trimmed_output) do
      {:ok, _parsed} ->
        {:ok, trimmed_output}

      {:error, _reason} ->
        extract_fenced_json(trimmed_output)
    end
  end

  defp extract_fenced_json(output) do
    case Regex.run(~r/```(?:json)?\s*(\{.*?\})\s*```/s, output, capture: :all_but_first) do
      [json_text] -> {:ok, json_text}
      _ -> {:error, "could not find strict JSON in opencode output"}
    end
  end
end
