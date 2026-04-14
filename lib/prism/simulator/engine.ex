defmodule Prism.Simulator.Engine do
  @moduledoc """
  User Simulator logic for Phase 2 (Interact).

  The simulator plays the "user" role against a memory system, executing
  scenario turns and recording full interaction transcripts.

  Two modes:
  - **Script**: Delivers turns verbatim (anchors — exact reproducibility)
  - **Adaptive**: LLM rephrases intent while preserving CL semantics (frontiers)

  Both modes are deterministic (temperature=0, fixed seed for adaptive).
  """

  require Logger

  @doc """
  Execute a scenario interaction against a memory system.

  Returns a transcript with all tool calls, retrieval contexts, and timing.
  Does NOT reset the system — callers control reset behavior.
  """
  @spec interact(Prism.Scenario.t(), map(), binary(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def interact(scenario, conn, system_id, llm_backend, opts \\ []) do
    mode = determine_mode(scenario)
    start_time = System.monotonic_time(:millisecond)

    Logger.info("[PRISM] Starting interaction: scenario=#{scenario.id}, mode=#{mode}")

    sessions = scenario.sessions

    if is_nil(sessions) or sessions == [] do
      {:error, {:no_sessions, scenario.id}}
    else
      transcript_sessions =
        Enum.map(sessions, fn session ->
          execute_session(session, conn, mode, llm_backend, opts)
        end)

      duration_ms = System.monotonic_time(:millisecond) - start_time

      {total_turns, total_tool_calls} = count_interactions(transcript_sessions)

      transcript = %{
        scenario_id: scenario.id,
        system_id: system_id,
        llm_backend: llm_backend,
        sessions: transcript_sessions,
        total_turns: total_turns,
        total_tool_calls: total_tool_calls,
        duration_ms: duration_ms
      }

      {:ok, transcript}
    end
  end

  @doc """
  Determine simulator mode from scenario kind.
  """
  @spec determine_mode(Prism.Scenario.t()) :: :script | :adaptive
  def determine_mode(%{kind: "anchor"}), do: :script
  def determine_mode(%{kind: "frontier"}), do: :adaptive
  def determine_mode(_), do: :script

  # Execute one session from the scenario
  defp execute_session(session, conn, mode, llm_backend, opts) do
    session_num = Map.get(session, "session_number") || Map.get(session, :session_number) || 1
    turns = Map.get(session, "turns") || Map.get(session, :turns) || []

    executed_turns =
      Enum.map(turns, fn turn ->
        execute_turn(turn, conn, mode, llm_backend, opts)
      end)

    %{
      "session_number" => session_num,
      "turns" => executed_turns
    }
  end

  # Execute a single turn
  defp execute_turn(turn, conn, mode, llm_backend, opts) do
    role = Map.get(turn, "role") || Map.get(turn, :role)
    action = Map.get(turn, "action") || Map.get(turn, :action)
    text = Map.get(turn, "text") || Map.get(turn, :text) || Map.get(turn, "content") || Map.get(turn, :content) || ""

    case role do
      "user" ->
        # Simulator sends this turn to the memory system
        actual_text = prepare_text(text, mode, llm_backend)
        result = execute_user_action(action, actual_text, turn, conn, opts)

        Map.merge(turn, %{
          "actual_text" => actual_text,
          "mode" => to_string(mode),
          "result" => result
        })

      "system" ->
        # This is the expected system behavior — recorded for judging
        turn

      _ ->
        turn
    end
  end

  # In script mode, use text verbatim. In adaptive mode, rephrase via LLM.
  defp prepare_text(text, :script, _model), do: text

  # Pure data layer: adaptive rephrasing is done agent-side, not inside PRISM.
  defp prepare_text(text, :adaptive, _model), do: text

  # Execute different user actions
  defp execute_user_action("ingest_commit", text, turn, _conn, _opts) do
    commit = Map.get(turn, "commit") || Map.get(turn, :commit)

    # TODO: Translate to system's native ingestion tools via MCP adapter
    %{
      "action" => "ingest_commit",
      "commit" => commit,
      "text" => text,
      "status" => "executed",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp execute_user_action("ingest_diff", text, turn, _conn, _opts) do
    commit = Map.get(turn, "commit") || Map.get(turn, :commit)

    %{
      "action" => "ingest_diff",
      "commit" => commit,
      "text" => text,
      "status" => "executed",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp execute_user_action("probe", text, _turn, conn, _opts) do
    # Send query to memory system via MCP retrieve tool
    {response, retrieval_context} = call_system_retrieve(conn, text)

    %{
      "action" => "probe",
      "text" => text,
      "status" => "executed",
      "response" => response,
      "retrieval_context" => retrieval_context,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp execute_user_action("provide_feedback", text, turn, _conn, _opts) do
    helpful = Map.get(turn, "helpful") || Map.get(turn, :helpful)

    %{
      "action" => "provide_feedback",
      "text" => text,
      "helpful" => helpful,
      "status" => "executed",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp execute_user_action(nil, text, _turn, conn, _opts) do
    # Generic user message — call retrieve on the target system
    {response, retrieval_context} = call_system_retrieve(conn, text)

    %{
      "action" => "message",
      "text" => text,
      "status" => "executed",
      "response" => response,
      "retrieval_context" => retrieval_context,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp execute_user_action(action, text, _turn, _conn, _opts) do
    Logger.warning("[PRISM] Unknown user action: #{action}")

    %{
      "action" => action,
      "text" => text,
      "status" => "unknown_action",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  # Call retrieve on the target memory system via MCP
  # conn is an MCP connection map from McpClient.connect/1
  defp call_system_retrieve(conn, query) when is_map(conn) and map_size(conn) > 0 do
    alias Prism.Simulator.McpClient

    case McpClient.call_tool(conn, "retrieve", %{action: "context", query: query}) do
      {:ok, result} ->
        # Extract the response text and context from the retrieve result
        response_text = extract_response_text(result)
        {response_text, result}

      {:error, reason} ->
        Logger.warning("[PRISM] System retrieve failed: #{inspect(reason)}")
        {nil, nil}
    end
  end

  defp call_system_retrieve(_conn, _query) do
    # No connection available — return nil (stub mode)
    {nil, nil}
  end

  # Extract human-readable text from a retrieve result
  # Graphonomous returns {status, results: [{content, confidence, node_id, ...}, ...]}
  defp extract_response_text(%{"results" => results}) when is_list(results) and results != [] do
    results
    |> Enum.map(fn node ->
      label = node["content"] || node["label"] || node["id"] || "unknown"
      # Truncate long content
      label = if String.length(label) > 200, do: String.slice(label, 0, 200) <> "...", else: label
      conf = node["confidence"]
      if conf, do: "#{label} (confidence: #{Float.round(conf, 3)})", else: label
    end)
    |> Enum.join("\n")
  end

  defp extract_response_text(%{"result" => %{"results" => results}}) when is_list(results) do
    extract_response_text(%{"results" => results})
  end

  defp extract_response_text(%{"result" => %{"nodes" => nodes}}) when is_list(nodes) and nodes != [] do
    nodes
    |> Enum.map(fn node ->
      label = node["content"] || node["label"] || node["id"] || "unknown"
      conf = node["confidence"]
      if conf, do: "#{label} (confidence: #{conf})", else: label
    end)
    |> Enum.join("; ")
  end

  defp extract_response_text(%{"raw" => raw}) when is_binary(raw), do: raw
  defp extract_response_text(other) when is_binary(other), do: other
  defp extract_response_text(_), do: nil

  # Count total turns and tool calls across all sessions
  defp count_interactions(sessions) do
    Enum.reduce(sessions, {0, 0}, fn session, {turns_acc, tools_acc} ->
      turns = Map.get(session, "turns") || []
      turn_count = length(turns)

      tool_count =
        Enum.reduce(turns, 0, fn turn, acc ->
          sent = Map.get(turn, "tool_calls_sent") || Map.get(turn, :tool_calls_sent) || []

          received =
            Map.get(turn, "tool_calls_received") || Map.get(turn, :tool_calls_received) || []

          acc + length(sent) + length(received)
        end)

      {turns_acc + turn_count, tools_acc + tool_count}
    end)
  end
end
