defmodule Hexguard.Runner do
  @moduledoc false

  def run_command(command, args, options) do
    allowed = Keyword.get(options, :allowed, [0])
    timeout = Keyword.get(options, :timeout, 300_000)
    stream? = Keyword.get(options, :stream?, false)
    log_verbose = Keyword.get(options, :log_verbose, fn _message, _metadata -> :ok end)
    pretty = Enum.join([command | args], " ")
    started_at = System.monotonic_time(:millisecond)

    log_verbose.("command start", %{command: pretty})

    runner_result = run_command_captured(command, args, timeout, stream?, log_verbose)

    case runner_result do
      {:ok, output, status} ->
        elapsed_ms = System.monotonic_time(:millisecond) - started_at

        if Enum.member?(allowed, status) do
          log_verbose.("command finish", %{
            command: pretty,
            status: status,
            elapsed_ms: elapsed_ms
          })

          {:ok, output}
        else
          log_verbose.("command failed", %{
            command: pretty,
            status: status,
            elapsed_ms: elapsed_ms
          })

          {:error, %{command: command, args: args, status: status, output: output}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp run_command_captured(command, args, timeout, true, _log_verbose) do
    case System.find_executable(command) do
      nil ->
        {:error, "executable not found: #{command}"}

      executable ->
        stream_mode = stream_output_mode(command, args)
        run_command_streaming_with_pty(executable, args, timeout, stream_mode)
    end
  end

  defp run_command_captured(command, args, timeout, false, log_verbose) do
    case System.find_executable(command) do
      nil ->
        {:error, "executable not found: #{command}"}

      executable ->
        task = Task.async(fn -> System.cmd(executable, args, stderr_to_stdout: true) end)
        await_command_task(task, executable, args, timeout, false, log_verbose)
    end
  end

  defp run_command_streaming_with_pty(executable, args, timeout, stream_mode) do
    command = Enum.map_join([executable | args], " ", &shell_escape/1)

    wrapper = "script -q /dev/null #{command}"

    port =
      Port.open({:spawn, wrapper}, [
        :binary,
        :exit_status,
        :stderr_to_stdout
      ])

    collect_streamed_output(
      port,
      [],
      timeout,
      System.monotonic_time(:millisecond),
      stream_mode,
      ""
    )
  end

  defp collect_streamed_output(port, acc, timeout, started_at, stream_mode, pending) do
    receive do
      {^port, {:data, data}} ->
        {formatted_output, new_pending} = format_stream_output(stream_mode, data, pending)

        if formatted_output != "" do
          IO.write(formatted_output)
        end

        collect_streamed_output(port, [acc, data], timeout, started_at, stream_mode, new_pending)

      {^port, {:exit_status, status}} ->
        {formatted_output, _new_pending} = format_stream_output(stream_mode, "\n", pending)

        if formatted_output != "" do
          IO.write(formatted_output)
        end

        {:ok, IO.iodata_to_binary(acc), status}
    after
      1_000 ->
        elapsed = System.monotonic_time(:millisecond) - started_at

        if elapsed >= timeout do
          Port.close(port)
          {:error, "command timed out after #{timeout}ms"}
        else
          collect_streamed_output(port, acc, timeout, started_at, stream_mode, pending)
        end
    end
  end

  defp stream_output_mode("opencode", args) do
    if opencode_json_format?(args), do: :opencode_json, else: :raw
  end

  defp stream_output_mode(_command, _args), do: :raw

  defp opencode_json_format?(args) do
    Enum.any?(args, &(&1 == "--format=json")) or
      Enum.any?(Enum.chunk_every(args, 2, 1, :discard), fn
        ["--format", "json"] -> true
        _ -> false
      end)
  end

  defp format_stream_output(:raw, data, pending), do: {data, pending}

  defp format_stream_output(:opencode_json, data, pending) do
    combined = pending <> data
    parts = String.split(combined, "\n", trim: false)

    case parts do
      [] ->
        {"", ""}

      _ ->
        complete_lines = Enum.drop(parts, -1)
        rest = List.last(parts)
        rendered = Enum.map_join(complete_lines, "", &render_opencode_json_line/1)
        {rendered, rest}
    end
  end

  defp render_opencode_json_line(line) do
    line = String.trim(line)

    if line == "" do
      ""
    else
      case JSON.decode(line) do
        {:ok, %{"type" => "text", "part" => %{"text" => text}}} when is_binary(text) ->
          text <> "\n"

        {:ok, %{"type" => "tool_use", "part" => %{"tool" => tool, "state" => state}}}
        when is_binary(tool) and is_map(state) ->
          render_tool_use_output(tool, state)

        {:ok, %{"type" => "step_start"}} ->
          IO.ANSI.format([:light_black, "[opencode] step started", :reset, "\n"])
          |> IO.iodata_to_binary()

        {:ok, %{"type" => "step_finish", "part" => %{"reason" => reason}}}
        when is_binary(reason) ->
          IO.ANSI.format([:light_black, "[opencode] step finished (", reason, ")", :reset, "\n"])
          |> IO.iodata_to_binary()

        {:ok, %{"type" => "error", "error" => %{"data" => %{"message" => message}}}}
        when is_binary(message) ->
          IO.ANSI.format([:red, "[opencode] error: #{message}", :reset, "\n"])
          |> IO.iodata_to_binary()

        _ ->
          ""
      end
    end
  end

  defp render_tool_use_output(tool, state) do
    status = Map.get(state, "status", "unknown")
    title = Map.get(state, "title")

    header =
      case title do
        value when is_binary(value) and value != "" ->
          IO.ANSI.format([:yellow, "[opencode][tool] ", tool, " (", status, "): ", value, :reset])
          |> IO.iodata_to_binary()

        _ ->
          IO.ANSI.format([:yellow, "[opencode][tool] ", tool, " (", status, ")", :reset])
          |> IO.iodata_to_binary()
      end

    output = Map.get(state, "output")

    case output do
      value when is_binary(value) and value != "" ->
        header <> "\n" <> value <> "\n"

      _ ->
        header <> "\n"
    end
  end

  defp await_command_task(task, executable, args, timeout, stream?, log_verbose) do
    started_at = System.monotonic_time(:millisecond)
    interval = 5_000

    do_await_command_task(
      task,
      executable,
      args,
      timeout,
      interval,
      started_at,
      stream?,
      log_verbose
    )
  end

  defp do_await_command_task(
         task,
         executable,
         args,
         timeout,
         interval,
         started_at,
         stream?,
         log_verbose
       ) do
    case Task.yield(task, interval) do
      {:ok, {output, status}} ->
        if stream?, do: IO.write(output)
        {:ok, output, status}

      nil ->
        elapsed = System.monotonic_time(:millisecond) - started_at

        if elapsed >= timeout do
          Task.shutdown(task, :brutal_kill)
          {:error, "command timed out after #{timeout}ms: #{Enum.join([executable | args], " ")}"}
        else
          log_verbose.("command still running", %{
            elapsed_ms: elapsed,
            command: Enum.join([executable | args], " ")
          })

          do_await_command_task(
            task,
            executable,
            args,
            timeout,
            interval,
            started_at,
            stream?,
            log_verbose
          )
        end
    end
  end

  defp shell_escape(value) do
    "'" <> String.replace(value, "'", "'\\''") <> "'"
  end
end
