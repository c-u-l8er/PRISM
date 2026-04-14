defmodule Prism.CLI do
  @moduledoc """
  Executable CLI entrypoint for PRISM MCP server over STDIO.

  Starts the PRISM OTP app (Ecto Repo + evaluation engine) and launches
  the MCP server transport on standard input/output.

      mix run --no-start --no-compile -e "Prism.CLI.main([])"
  """

  require Logger

  @default_request_timeout 120_000

  @spec main([String.t()]) :: no_return()
  def main(args) when is_list(args) do
    case parse_args(args) do
      {:help} ->
        IO.puts(help_text())
        System.halt(0)

      {:ok, opts} ->
        configure_runtime(opts)
        # Signal to Prism.Application that we're in CLI/STDIO mode
        # so it skips the HTTP MCP server child.
        Application.put_env(:prism, :mcp_mode, :stdio)
        Process.flag(:trap_exit, true)
        start_runtime()
        {:ok, monitor_pid} = start_mcp_server(opts)
        wait_forever(monitor_pid)

      {:error, message} ->
        IO.puts(:stderr, "prism: #{message}\n")
        IO.puts(:stderr, help_text())
        System.halt(1)
    end
  end

  defp parse_args(args) do
    {parsed, _rest, invalid} =
      OptionParser.parse(args,
        strict: [
          help: :boolean,
          db: :string,
          log_level: :string,
          request_timeout: :integer
        ],
        aliases: [h: :help, d: :db]
      )

    cond do
      parsed[:help] -> {:help}
      invalid != [] -> {:error, "invalid option(s): #{format_invalid(invalid)}"}
      true -> normalize_options(parsed)
    end
  end

  defp normalize_options(parsed) do
    opts =
      %{}
      |> maybe_put(:db_path, parsed[:db])
      |> maybe_put(:log_level, normalize_log_level(parsed[:log_level]))
      |> maybe_put(:request_timeout, parsed[:request_timeout])

    {:ok, opts}
  end

  defp configure_runtime(opts) do
    if db = Map.get(opts, :db_path) do
      db_path = expand_path(db)
      File.mkdir_p!(Path.dirname(db_path))
      Application.put_env(:prism, Prism.Repo, database: db_path, journal_mode: :wal, pool_size: 1)
    end

    if level = Map.get(opts, :log_level) do
      Logger.configure(level: level)
    end

    # Keep stdout clean for MCP protocol frames.
    # Must redirect the OTP default handler BEFORE starting apps so that
    # early Logger.error calls (e.g. file_system inotify check) don't
    # contaminate the MCP STDIO protocol stream.
    force_stderr_logging!()

    # Disable noisy Anubis logs during MCP handshake
    Application.put_env(:anubis_mcp, :log, false)

    :ok
  end

  defp start_runtime do
    case Application.ensure_all_started(:prism) do
      {:ok, _started} -> :ok
      {:error, reason} -> halt_with_error("failed to start prism: #{inspect(reason)}")
    end

    case Application.ensure_all_started(:anubis_mcp) do
      {:ok, _started} -> :ok
      {:error, reason} -> halt_with_error("failed to start anubis_mcp: #{inspect(reason)}")
    end

    # Run migrations automatically for SQLite
    run_migrations()
  end

  defp run_migrations do
    Ecto.Migrator.run(Prism.Repo, migrations_path(), :up, all: true, log: false)
  rescue
    e -> Logger.warning("Migration skipped: #{inspect(e)}")
  end

  defp migrations_path do
    priv_dir =
      case :code.priv_dir(:prism) do
        {:error, _} -> Path.join(File.cwd!(), "priv")
        dir -> List.to_string(dir)
      end

    Path.join(priv_dir, "repo/migrations")
  end

  defp start_mcp_server(opts) do
    timeout = Map.get(opts, :request_timeout, @default_request_timeout)

    case Anubis.Server.Supervisor.start_link(
           Prism.MCP.Machines.Server,
           transport: :stdio,
           request_timeout: timeout
         ) do
      {:ok, supervisor_pid} ->
        {:ok, resolve_monitor_pid(supervisor_pid)}

      {:error, {:already_started, supervisor_pid}} ->
        {:ok, resolve_monitor_pid(supervisor_pid)}

      {:error, reason} ->
        halt_with_error("failed to start MCP server: #{inspect(reason)}")
    end
  end

  defp resolve_monitor_pid(supervisor_pid) do
    case resolve_transport_pid(20) do
      pid when is_pid(pid) -> pid
      _ -> supervisor_pid
    end
  end

  defp resolve_transport_pid(0), do: nil

  defp resolve_transport_pid(attempts) do
    case Anubis.Server.Registry.whereis_transport(Prism.MCP.Machines.Server, :stdio) do
      pid when is_pid(pid) -> pid
      _ ->
        Process.sleep(10)
        resolve_transport_pid(attempts - 1)
    end
  end

  defp wait_forever(monitor_pid) do
    ref = Process.monitor(monitor_pid)

    receive do
      {:DOWN, ^ref, :process, ^monitor_pid, reason} ->
        handle_termination(reason)

      {:EXIT, ^monitor_pid, reason} ->
        handle_termination(reason)
    after
      :infinity -> System.halt(0)
    end
  end

  defp handle_termination(reason) when reason in [:normal, :shutdown, :eof], do: System.halt(0)
  defp handle_termination({:error, :eof}), do: System.halt(0)
  defp handle_termination({:shutdown, :normal}), do: System.halt(0)
  defp handle_termination({:shutdown, {:error, :eof}}), do: System.halt(0)
  defp handle_termination(reason), do: halt_with_error("MCP server terminated: #{inspect(reason)}")

  defp normalize_log_level(nil), do: :error
  defp normalize_log_level("debug"), do: :debug
  defp normalize_log_level("info"), do: :info
  defp normalize_log_level("warning"), do: :warning
  defp normalize_log_level("error"), do: :error
  defp normalize_log_level(_), do: :error

  defp expand_path("~/" <> rest), do: Path.join(System.get_env("HOME", ""), rest)
  defp expand_path(path), do: Path.expand(path)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp format_invalid(invalid) do
    invalid
    |> Enum.map(fn {key, value} -> "--#{key}=#{inspect(value)}" end)
    |> Enum.join(", ")
  end

  defp halt_with_error(message) do
    IO.puts(:stderr, "prism: #{message}")
    System.halt(1)
  end

  defp force_stderr_logging! do
    Logger.configure_backend(:console, device: :standard_error)

    # OTP's logger_std_h refuses to change :type after init, so we must
    # remove and re-add the default handler with :standard_error.
    try do
      case :logger.get_handler_config(:default) do
        {:ok, %{module: module, config: config} = handler} ->
          :logger.remove_handler(:default)

          new_config = Map.put(config, :type, :standard_error)

          :logger.add_handler(
            :default,
            module,
            Map.put(handler, :config, new_config)
          )

        _ ->
          :ok
      end
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end

    :ok
  end

  defp help_text do
    """
    PRISM CLI — Self-Improving CL Evaluation Engine

    Usage:
      mix run --no-start --no-compile -e "Prism.CLI.main([])" -- [options]

    Options:
      -h, --help                 Show this help
      -d, --db PATH              SQLite DB path (default: ~/.prism/prism.db)
          --log-level LEVEL      debug | info | warning | error
          --request-timeout MS   MCP request timeout in milliseconds

    Environment variables:
      PRISM_DB_PATH              SQLite database path
      PRISM_LOG_LEVEL            Log level
      PRISM_REQUEST_TIMEOUT      MCP request timeout

    Examples:
      # Start MCP server with default SQLite
      mix run --no-start --no-compile -e "Prism.CLI.main([])"

      # Custom database path
      mix run --no-start --no-compile -e "Prism.CLI.main([\"--db\",\"~/.prism/benchmark.db\"])"
    """
  end
end
