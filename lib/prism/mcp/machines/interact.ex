defmodule Prism.MCP.Machines.Interact do
  @moduledoc """
  Loop Phase 2: INTERACT — "Run the test"

  Unified interaction machine for the PRISM evaluation loop.
  The agent calls this to execute scenarios against memory systems.

  Actions:
  - `run`           — One scenario × one system
  - `run_sequence`  — Scenario sequence, no memory reset
  - `run_matrix`    — N systems × M models × all scenarios
  - `status`        — Check in-progress run
  - `transcript`    — Full interaction transcript
  - `cancel`        — Cancel in-progress run
  - `byor_evaluate` — Full BYOR evaluation
  - `byor_compare`  — Head-to-head on your repo

  Replaces: run_interaction, run_sequence, run_matrix,
            get_run_status, get_transcript, cancel_run,
            byor_evaluate, byor_compare
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  @valid_actions ~w(run run_sequence run_matrix status transcript cancel byor_evaluate byor_compare)

  schema do
    field(:action, :string,
      required: true,
      description:
        "Interaction action: run | run_sequence | run_matrix | status | transcript | cancel | byor_evaluate | byor_compare"
    )

    field(:scenario_id, :string, description: "Scenario UUID (run)")
    field(:system_id, :string, description: "System ID (run, run_sequence, byor_evaluate, byor_compare)")
    field(:llm_backend, :string, description: "LLM model powering the memory system (run, run_sequence)")
    field(:sequence_id, :string, description: "Sequence UUID (run_sequence)")
    field(:suite_id, :string, description: "Suite UUID (run_matrix)")
    field(:systems, :string, description: "JSON array of system IDs (run_matrix)")
    field(:models, :string, description: "JSON array of LLM backends (run_matrix)")
    field(:run_id, :string, description: "Run UUID (status, cancel)")
    field(:transcript_id, :string, description: "Transcript UUID (transcript)")

    # byor
    field(:repo_anchor_id, :string, description: "Repo anchor UUID (byor_evaluate, byor_compare)")
    field(:system_a, :string, description: "First system for comparison (byor_compare)")
    field(:system_b, :string, description: "Second system for comparison (byor_compare)")
  end

  @impl true
  def execute(params, frame) do
    action = params |> p(:action) |> normalize_action()

    if action in @valid_actions do
      dispatch(action, params, frame)
    else
      {:reply,
       error_response(
         "Invalid action '#{inspect(p(params, :action))}'. Must be one of: #{Enum.join(@valid_actions, ", ")}"
       ), frame}
    end
  end

  defp dispatch("run", params, frame) do
    with sid when not is_nil(sid) <- p(params, :scenario_id),
         sysid when not is_nil(sysid) <- p(params, :system_id),
         llm when not is_nil(llm) <- p(params, :llm_backend),
         scenario when not is_nil(scenario) <- Prism.Scenario.Library.get(sid) do
      case Prism.Simulator.Engine.interact(scenario, %{}, sysid, llm) do
        {:ok, result} ->
          # Persist the transcript to DB
          transcript_attrs = %{
            scenario_id: sid,
            system_id: sysid,
            llm_backend: llm,
            sessions: result.sessions,
            total_turns: result.total_turns,
            total_tool_calls: result.total_tool_calls,
            duration_ms: result.duration_ms
          }

          case Prism.Repo.insert(Prism.Transcript.changeset(%Prism.Transcript{}, transcript_attrs)) do
            {:ok, transcript} ->
              {:reply, success_response(Map.put(result, :transcript_id, transcript.id)), frame}

            {:error, changeset} ->
              # Return result even if persistence fails, with warning
              {:reply,
               success_response(
                 Map.merge(result, %{
                   transcript_id: nil,
                   persistence_warning: "Failed to persist: #{inspect(changeset.errors)}"
                 })
               ), frame}
          end

        {:error, reason} ->
          {:reply, error_response(inspect(reason)), frame}
      end
    else
      nil -> {:reply, error_response("scenario_id, system_id, and llm_backend required"), frame}
    end
  end

  defp dispatch("run_sequence", params, frame) do
    with seqid when not is_nil(seqid) <- p(params, :sequence_id),
         sysid when not is_nil(sysid) <- p(params, :system_id),
         llm when not is_nil(llm) <- p(params, :llm_backend),
         sequence when not is_nil(sequence) <- Prism.Repo.get(Prism.Sequence, seqid) do
      case Prism.Sequence.Runner.run(sequence, sysid, llm) do
        {:ok, result} -> {:reply, success_response(result), frame}
        {:error, reason} -> {:reply, error_response(inspect(reason)), frame}
      end
    else
      nil -> {:reply, error_response("sequence_id, system_id, and llm_backend required"), frame}
    end
  end

  defp dispatch("run_matrix", params, frame) do
    suite_id = p(params, :suite_id)
    systems_json = p(params, :systems)
    models_json = p(params, :models)

    with systems when is_list(systems) <- parse_json_array(systems_json),
         models when is_list(models) <- parse_json_array(models_json) do
      # Load scenarios — either from suite or all active scenarios
      scenarios =
        case suite_id do
          nil -> Prism.Scenario.Library.list()
          _id -> Prism.Scenario.Library.list()
        end

      # Create a run record for tracking
      results =
        for system_id <- systems,
            llm <- models,
            scenario <- scenarios do
          case Prism.Simulator.Engine.interact(scenario, %{}, system_id, llm) do
            {:ok, result} ->
              transcript_attrs = %{
                scenario_id: scenario.id,
                system_id: system_id,
                llm_backend: llm,
                sessions: result.sessions,
                total_turns: result.total_turns,
                total_tool_calls: result.total_tool_calls,
                duration_ms: result.duration_ms
              }

              tid =
                case Prism.Repo.insert(
                       Prism.Transcript.changeset(%Prism.Transcript{}, transcript_attrs)
                     ) do
                  {:ok, t} -> t.id
                  _ -> nil
                end

              %{
                system_id: system_id,
                llm_backend: llm,
                scenario_id: scenario.id,
                status: "ok",
                transcript_id: tid
              }

            {:error, reason} ->
              %{
                system_id: system_id,
                llm_backend: llm,
                scenario_id: scenario.id,
                status: "error",
                error: inspect(reason)
              }
          end
        end

      successes = Enum.count(results, &(&1.status == "ok"))

      {:reply,
       success_response(%{
         total: length(results),
         successes: successes,
         failures: length(results) - successes,
         systems: length(systems),
         models: length(models),
         scenarios: length(scenarios),
         results: results
       }), frame}
    else
      _ -> {:reply, error_response("systems and models must be JSON arrays"), frame}
    end
  end

  defp dispatch("status", params, frame) do
    case p(params, :run_id) do
      nil ->
        {:reply, error_response("run_id required"), frame}

      id ->
        case Prism.Repo.get(Prism.Run, id) do
          nil -> {:reply, error_response("run not found: #{id}"), frame}
          run -> {:reply, success_response(%{status: run.status, started_at: run.started_at, completed_at: run.completed_at}), frame}
        end
    end
  end

  defp dispatch("transcript", params, frame) do
    case p(params, :transcript_id) do
      nil ->
        {:reply, error_response("transcript_id required"), frame}

      id ->
        case Prism.Repo.get(Prism.Transcript, id) do
          nil -> {:reply, error_response("transcript not found: #{id}"), frame}
          transcript -> {:reply, success_response(transcript_to_map(transcript)), frame}
        end
    end
  end

  defp dispatch("cancel", params, frame) do
    case p(params, :run_id) do
      nil ->
        {:reply, error_response("run_id required"), frame}

      id ->
        case Prism.Repo.get(Prism.Run, id) do
          nil ->
            {:reply, error_response("run not found: #{id}"), frame}

          run ->
            changeset = Prism.Run.status_changeset(run, "cancelled")

            case Prism.Repo.update(changeset) do
              {:ok, updated} -> {:reply, success_response(%{status: updated.status}), frame}
              {:error, reason} -> {:reply, error_response(inspect(reason)), frame}
            end
        end
    end
  end

  defp dispatch("byor_evaluate", params, frame) do
    system_id = p(params, :system_id)
    repo_anchor_id = p(params, :repo_anchor_id)
    llm_backend = p(params, :llm_backend) || "agent"

    with system_id when not is_nil(system_id) <- system_id,
         repo_anchor_id when not is_nil(repo_anchor_id) <- repo_anchor_id,
         anchor when not is_nil(anchor) <- Prism.Repo.get(Prism.RepoAnchor, repo_anchor_id) do
      # Get scenarios linked to this repo anchor
      import Ecto.Query

      scenarios =
        from(s in Prism.Scenario,
          where: s.repo_anchor_id == ^anchor.id and is_nil(s.retired_at),
          select: s
        )
        |> Prism.Repo.all()

      if scenarios == [] do
        {:reply, error_response("No active scenarios found for repo anchor #{repo_anchor_id}"), frame}
      else
        results =
          Enum.map(scenarios, fn scenario ->
            case Prism.Simulator.Engine.interact(scenario, %{}, system_id, llm_backend) do
              {:ok, result} ->
                transcript_attrs = %{
                  scenario_id: scenario.id,
                  system_id: system_id,
                  llm_backend: llm_backend,
                  sessions: result.sessions,
                  total_turns: result.total_turns,
                  total_tool_calls: result.total_tool_calls,
                  duration_ms: result.duration_ms
                }

                tid =
                  case Prism.Repo.insert(Prism.Transcript.changeset(%Prism.Transcript{}, transcript_attrs)) do
                    {:ok, t} -> t.id
                    _ -> nil
                  end

                %{scenario_id: scenario.id, status: "ok", transcript_id: tid}

              {:error, reason} ->
                %{scenario_id: scenario.id, status: "error", error: inspect(reason)}
            end
          end)

        successes = Enum.count(results, &(&1.status == "ok"))

        {:reply,
         success_response(%{
           system_id: system_id,
           repo_anchor_id: repo_anchor_id,
           total: length(results),
           successes: successes,
           failures: length(results) - successes,
           results: results
         }), frame}
      end
    else
      nil ->
        {:reply, error_response("system_id and repo_anchor_id required (repo anchor must exist)"), frame}
    end
  end

  defp dispatch("byor_compare", params, frame) do
    system_a = p(params, :system_a)
    system_b = p(params, :system_b)
    repo_anchor_id = p(params, :repo_anchor_id)
    llm_backend = p(params, :llm_backend) || "agent"

    with system_a when not is_nil(system_a) <- system_a,
         system_b when not is_nil(system_b) <- system_b,
         repo_anchor_id when not is_nil(repo_anchor_id) <- repo_anchor_id,
         anchor when not is_nil(anchor) <- Prism.Repo.get(Prism.RepoAnchor, repo_anchor_id) do
      import Ecto.Query

      scenarios =
        from(s in Prism.Scenario,
          where: s.repo_anchor_id == ^anchor.id and is_nil(s.retired_at),
          select: s
        )
        |> Prism.Repo.all()

      if scenarios == [] do
        {:reply, error_response("No active scenarios found for repo anchor"), frame}
      else
        run_system = fn sys_id ->
          Enum.map(scenarios, fn scenario ->
            case Prism.Simulator.Engine.interact(scenario, %{}, sys_id, llm_backend) do
              {:ok, result} ->
                transcript_attrs = %{
                  scenario_id: scenario.id,
                  system_id: sys_id,
                  llm_backend: llm_backend,
                  sessions: result.sessions,
                  total_turns: result.total_turns,
                  total_tool_calls: result.total_tool_calls,
                  duration_ms: result.duration_ms
                }

                tid =
                  case Prism.Repo.insert(Prism.Transcript.changeset(%Prism.Transcript{}, transcript_attrs)) do
                    {:ok, t} -> t.id
                    _ -> nil
                  end

                %{scenario_id: scenario.id, status: "ok", transcript_id: tid}

              {:error, reason} ->
                %{scenario_id: scenario.id, status: "error", error: inspect(reason)}
            end
          end)
        end

        results_a = run_system.(system_a)
        results_b = run_system.(system_b)

        {:reply,
         success_response(%{
           repo_anchor_id: repo_anchor_id,
           system_a: %{id: system_a, results: results_a, successes: Enum.count(results_a, &(&1.status == "ok"))},
           system_b: %{id: system_b, results: results_b, successes: Enum.count(results_b, &(&1.status == "ok"))}
         }), frame}
      end
    else
      nil ->
        {:reply, error_response("system_a, system_b, and repo_anchor_id required"), frame}
    end
  end

  # -- Helpers --

  defp normalize_action(nil), do: nil
  defp normalize_action(v) when is_binary(v), do: v |> String.trim() |> String.downcase()
  defp normalize_action(v) when is_atom(v), do: Atom.to_string(v)
  defp normalize_action(_), do: nil

  defp success_response(result) do
    Response.tool()
    |> Response.structured(%{status: "ok", result: result})
  end

  defp error_response(message) do
    Response.tool()
    |> Response.structured(%{status: "error", error: message})
    |> Map.put(:isError, true)
  end

  defp parse_json_array(nil), do: nil

  defp parse_json_array(v) when is_binary(v) do
    case Jason.decode(v) do
      {:ok, list} when is_list(list) -> list
      _ -> nil
    end
  end

  defp parse_json_array(v) when is_list(v), do: v
  defp parse_json_array(_), do: nil

  defp transcript_to_map(%Prism.Transcript{} = t) do
    %{
      id: t.id,
      scenario_id: t.scenario_id,
      system_id: t.system_id,
      run_id: t.run_id,
      llm_backend: t.llm_backend,
      sessions: t.sessions,
      total_turns: t.total_turns,
      total_tool_calls: t.total_tool_calls,
      duration_ms: t.duration_ms,
      created_at: t.created_at && DateTime.to_iso8601(t.created_at)
    }
  end

  defp p(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end
end
