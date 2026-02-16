defmodule Hexguard.Lockfile do
  @moduledoc false

  alias Mix.Dep.Lock

  def read_versions do
    lock = Lock.read()

    versions =
      Enum.reduce(lock, %{}, fn {name, data}, acc ->
        case data do
          {:hex, _package, version, _checksum, _managers, _deps, _repo, _outer_checksum} ->
            Map.put(acc, Atom.to_string(name), version)

          _ ->
            acc
        end
      end)

    {:ok, versions}
  rescue
    error -> {:error, Exception.message(error)}
  end

  def changes(before_versions, after_versions)
      when is_map(before_versions) and is_map(after_versions) do
    before_versions
    |> Map.keys()
    |> Enum.concat(Map.keys(after_versions))
    |> Enum.uniq()
    |> Enum.reduce([], fn dep, acc ->
      from = Map.get(before_versions, dep)
      to = Map.get(after_versions, dep)

      if from != to and is_binary(from) and is_binary(to) do
        [%{dep: dep, from: from, to: to} | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end
end
