defmodule Hexguard.Opencode do
  @moduledoc false

  alias Hexguard.Runner

  @restricted_opencode_image "ghcr.io/anomalyco/opencode"
  @restricted_workspace "/workspace"
  @security_diff_path "/tmp/dependency_diff.md"
  @runner_option_keys [:allowed, :timeout, :stream?, :log_verbose]
  @passthrough_env_vars ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GH_TOKEN", "GITHUB_TOKEN"]

  def run(opencode_args, options \\ []) when is_list(opencode_args) and is_list(options) do
    Runner.run_command("opencode", opencode_args, options)
  end

  def run_docker(opencode_args, options \\ []) when is_list(opencode_args) and is_list(options) do
    runner_options = Keyword.take(options, @runner_option_keys)
    workspace_mount? = Keyword.get(options, :workspace_mount?, true)
    security_profile? = Keyword.get(options, :security_profile?, false)
    mount_config? = Keyword.get(options, :mount_config?, true)
    mount_data? = Keyword.get(options, :mount_data?, true)
    extra_mounts = Keyword.get(options, :extra_mounts, [])

    cwd = File.cwd!()
    home = System.user_home!()
    config_path = Path.join(home, ".config/opencode")
    data_path = Path.join(home, ".local/share/opencode")

    workspace_mount_args =
      if workspace_mount? do
        ["-v", "#{cwd}:#{@restricted_workspace}", "-w", @restricted_workspace]
      else
        []
      end

    extra_mount_args =
      Enum.flat_map(extra_mounts, fn
        {host_path, container_path} ->
          ["-v", "#{Path.expand(host_path)}:#{container_path}"]

        {host_path, container_path, :ro} ->
          ["-v", "#{Path.expand(host_path)}:#{container_path}:ro"]
      end)

    config_mount_args =
      if mount_config?, do: ["-v", "#{config_path}:/root/.config/opencode"], else: []

    data_mount_args =
      if mount_data?, do: ["-v", "#{data_path}:/root/.local/share/opencode"], else: []

    security_profile_args =
      if security_profile? do
        [
          "--cap-drop",
          "ALL",
          "--security-opt",
          "no-new-privileges:true",
          "--pids-limit",
          "128",
          "--memory",
          "1g",
          "--cpus",
          "1.0",
          "-e",
          "SHELL=/nonexistent"
        ]
      else
        []
      end

    args =
      ["run", "--rm"] ++
        passthrough_env_args() ++
        config_mount_args ++
        data_mount_args ++
        security_profile_args ++
        workspace_mount_args ++
        extra_mount_args ++
        [@restricted_opencode_image] ++
        opencode_args

    Runner.run_command("docker", args, runner_options)
  end

  def docker_workspace_path(path) when is_binary(path) do
    cwd = File.cwd!()
    absolute_path = Path.expand(path)
    relative = Path.relative_to(absolute_path, cwd)

    if String.starts_with?(relative, "..") do
      absolute_path
    else
      Path.join(@restricted_workspace, relative)
    end
  end

  def security_diff_path, do: @security_diff_path

  defp passthrough_env_args do
    Enum.flat_map(@passthrough_env_vars, fn env_var ->
      if System.get_env(env_var) do
        ["-e", env_var]
      else
        []
      end
    end)
  end
end
