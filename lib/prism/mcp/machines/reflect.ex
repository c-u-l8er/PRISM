defmodule Prism.MCP.Machines.Reflect do
  @moduledoc """
  Loop Phase 4: REFLECT — "What should change?"

  Unified reflection machine for the PRISM evaluation loop.
  The agent calls this to evolve scenarios and improve the benchmark.

  Actions:
  - `analyze_gaps`      — Under-tested dims, saturated scenarios, domain gaps
  - `evolve`            — Retire, extend, fork, promote
  - `advance_cycle`     — Run all 4 phases (Compose → Interact → Observe → Reflect)
  - `calibrate_irt`     — Recalibrate IRT difficulty/discrimination
  - `cycle_history`     — Full history of cycles and improvements
  - `byor_recommend`    — System recommendation for your use case
  - `byor_infer_profile` — Infer task profile from repo patterns

  Replaces: analyze_gaps, evolve_scenarios, advance_cycle,
            calibrate_irt, get_cycle_history,
            byor_recommend, byor_infer_profile
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  @valid_actions ~w(analyze_gaps evolve advance_cycle calibrate_irt cycle_history byor_recommend byor_infer_profile)

  schema do
    field(:action, :string,
      required: true,
      description:
        "Reflection action: analyze_gaps | evolve | advance_cycle | calibrate_irt | cycle_history | byor_recommend | byor_infer_profile"
    )

    field(:cycle, :number, description: "Cycle number (analyze_gaps, evolve)")

    field(:recommendations, :string,
      description: "JSON array of gap analysis recommendations to apply (evolve)"
    )

    # byor
    field(:repo_anchor_id, :string, description: "Repo anchor UUID (byor_recommend, byor_infer_profile)")
    field(:budget, :string, description: "Budget constraint (byor_recommend)")
    field(:priorities, :string, description: "JSON object of dimension priorities (byor_recommend)")
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

  defp dispatch("analyze_gaps", params, frame) do
    cycle = p(params, :cycle) && trunc(p(params, :cycle))

    case Prism.Cycle.Manager.analyze_gaps(cycle) do
      {:ok, result} -> {:reply, success_response(result), frame}
      {:error, reason} -> {:reply, error_response(inspect(reason)), frame}
    end
  end

  defp dispatch("evolve", params, frame) do
    recs_json = p(params, :recommendations)

    case parse_json_array(recs_json) do
      nil ->
        {:reply, error_response("recommendations JSON array required"), frame}

      recommendations ->
        results =
          Enum.map(recommendations, fn rec ->
            action = Map.get(rec, "action", Map.get(rec, "type", "unknown"))
            scenario_id = Map.get(rec, "scenario_id")
            reason = Map.get(rec, "reason", "evolved")

            case action do
              "retire" when not is_nil(scenario_id) ->
                evolve_retire(scenario_id, reason)

              "promote" when not is_nil(scenario_id) ->
                evolve_promote(scenario_id)

              "fork" when not is_nil(scenario_id) ->
                evolve_fork(scenario_id, rec)

              _ ->
                %{action: action, status: "skipped", reason: "unrecognized or missing scenario_id"}
            end
          end)

        applied = Enum.count(results, &(&1.status == "ok"))

        {:reply,
         success_response(%{
           total: length(results),
           applied: applied,
           results: results
         }), frame}
    end
  end

  defp dispatch("advance_cycle", _params, frame) do
    case Prism.Cycle.Manager.advance_cycle() do
      {:ok, result} -> {:reply, success_response(result), frame}
      {:error, reason} -> {:reply, error_response(inspect(reason)), frame}
    end
  end

  defp dispatch("calibrate_irt", _params, frame) do
    Prism.IRT.Calibrator.recalibrate([])
    result = Prism.IRT.Calibrator.summary()
    {:reply, success_response(result), frame}
  end

  defp dispatch("cycle_history", _params, frame) do
    result = Prism.Cycle.Manager.history()
    {:reply, success_response(result), frame}
  end

  defp dispatch("byor_recommend", params, frame) do
    repo_anchor_id = p(params, :repo_anchor_id)
    budget = p(params, :budget)
    priorities_json = p(params, :priorities)

    with repo_anchor_id when not is_nil(repo_anchor_id) <- repo_anchor_id,
         anchor when not is_nil(anchor) <- Prism.Repo.get(Prism.RepoAnchor, repo_anchor_id) do
      # Infer priorities from repo events if not provided
      priorities =
        case parse_json_object(priorities_json) do
          nil -> infer_priorities_from_anchor(anchor)
          p -> p
        end

      # Get all leaderboard entries
      entries = Prism.Leaderboard.get([])

      # Score each system against inferred priorities
      scored =
        Enum.map(entries, fn entry ->
          fit_score = compute_profile_fit(entry, priorities)
          %{system: entry[:system_name], fit_score: fit_score, weighted_total: entry[:weighted_total]}
        end)
        |> Enum.sort_by(& &1.fit_score, :desc)

      {:reply,
       success_response(%{
         repo_anchor_id: repo_anchor_id,
         inferred_priorities: priorities,
         budget: budget,
         recommendations: scored
       }), frame}
    else
      nil -> {:reply, error_response("repo_anchor_id required (anchor must exist)"), frame}
    end
  end

  defp dispatch("byor_infer_profile", params, frame) do
    repo_anchor_id = p(params, :repo_anchor_id)

    with repo_anchor_id when not is_nil(repo_anchor_id) <- repo_anchor_id,
         anchor when not is_nil(anchor) <- Prism.Repo.get(Prism.RepoAnchor, repo_anchor_id) do
      priorities = infer_priorities_from_anchor(anchor)

      # Determine dominant domains from key events
      domains =
        (anchor.key_events || [])
        |> Enum.flat_map(fn e -> Map.get(e, "domains") || Map.get(e, :domains) || [] end)
        |> Enum.frequencies()
        |> Enum.sort_by(fn {_, c} -> -c end)
        |> Enum.map(fn {d, _} -> d end)
        |> Enum.take(3)

      profile = %{
        id: Ecto.UUID.generate(),
        name: "inferred-from-#{anchor.id |> String.slice(0..7)}",
        dimension_priorities: priorities,
        domains: if(domains == [], do: ["code"], else: domains),
        total_commits: anchor.total_commits,
        repo_url: anchor.repo_url,
        created_at: DateTime.utc_now()
      }

      # Store in ETS
      :ets.insert(:prism_task_profiles, {profile.id, profile})

      {:reply, success_response(profile), frame}
    else
      nil -> {:reply, error_response("repo_anchor_id required (anchor must exist)"), frame}
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

  defp evolve_retire(scenario_id, reason) do
    case Prism.Repo.get(Prism.Scenario, scenario_id) do
      nil ->
        %{action: "retire", scenario_id: scenario_id, status: "error", error: "not found"}

      scenario ->
        changeset = Prism.Scenario.retire_changeset(scenario, reason)

        case Prism.Repo.update(changeset) do
          {:ok, _} -> %{action: "retire", scenario_id: scenario_id, status: "ok"}
          {:error, cs} -> %{action: "retire", scenario_id: scenario_id, status: "error", error: inspect(cs.errors)}
        end
    end
  end

  defp evolve_promote(scenario_id) do
    case Prism.Repo.get(Prism.Scenario, scenario_id) do
      nil ->
        %{action: "promote", scenario_id: scenario_id, status: "error", error: "not found"}

      scenario ->
        changeset = Prism.Scenario.promote_changeset(scenario)

        case Prism.Repo.update(changeset) do
          {:ok, _} -> %{action: "promote", scenario_id: scenario_id, status: "ok"}
          {:error, cs} -> %{action: "promote", scenario_id: scenario_id, status: "error", error: inspect(cs.errors)}
        end
    end
  end

  defp evolve_fork(scenario_id, rec) do
    case Prism.Repo.get(Prism.Scenario, scenario_id) do
      nil ->
        %{action: "fork", scenario_id: scenario_id, status: "error", error: "not found"}

      scenario ->
        # Fork creates a new frontier scenario based on the original
        new_attrs = %{
          kind: "frontier",
          domain: Map.get(rec, "domain", scenario.domain),
          difficulty: Map.get(rec, "difficulty", scenario.difficulty),
          persona: scenario.persona,
          sessions: scenario.sessions,
          cl_challenges: scenario.cl_challenges,
          suite_id: scenario.suite_id
        }

        case Prism.Repo.insert(Prism.Scenario.changeset(%Prism.Scenario{}, new_attrs)) do
          {:ok, new_scenario} ->
            %{action: "fork", scenario_id: scenario_id, new_id: new_scenario.id, status: "ok"}

          {:error, cs} ->
            %{action: "fork", scenario_id: scenario_id, status: "error", error: inspect(cs.errors)}
        end
    end
  end

  defp infer_priorities_from_anchor(anchor) do
    events = anchor.key_events || []

    # Count which CL dimensions are represented in key events
    dim_counts =
      events
      |> Enum.flat_map(fn e ->
        Map.get(e, "cl_dimensions") || Map.get(e, :cl_dimensions) || []
      end)
      |> Enum.map(&to_string/1)
      |> Enum.frequencies()

    if map_size(dim_counts) == 0 do
      # Default balanced priorities
      Prism.Benchmark.CLCategories.dimension_strings()
      |> Enum.map(&{&1, 1.0})
      |> Map.new()
    else
      max_count = dim_counts |> Map.values() |> Enum.max(fn -> 1 end)

      dim_counts
      |> Enum.map(fn {dim, count} -> {dim, Float.round(count / max_count, 2)} end)
      |> Map.new()
    end
  end

  defp compute_profile_fit(entry, priorities) do
    dim_map = %{
      "stability" => entry[:stability_score],
      "plasticity" => entry[:plasticity_score],
      "knowledge_update" => entry[:knowledge_update_score],
      "temporal" => entry[:temporal_score],
      "consolidation" => entry[:consolidation_score],
      "epistemic_awareness" => entry[:uncertainty_score],
      "transfer" => entry[:transfer_score],
      "forgetting" => entry[:forgetting_score],
      "feedback" => entry[:feedback_score]
    }

    total_weight = priorities |> Map.values() |> Enum.sum() |> max(1.0)

    priorities
    |> Enum.map(fn {dim, weight} ->
      score = Map.get(dim_map, dim, 0.0) || 0.0
      score * weight
    end)
    |> Enum.sum()
    |> Kernel./(total_weight)
    |> Float.round(4)
  end

  defp parse_json_object(nil), do: nil

  defp parse_json_object(v) when is_binary(v) do
    case Jason.decode(v) do
      {:ok, map} when is_map(map) -> map
      _ -> nil
    end
  end

  defp parse_json_object(v) when is_map(v), do: v
  defp parse_json_object(_), do: nil

  defp parse_json_array(nil), do: nil

  defp parse_json_array(v) when is_binary(v) do
    case Jason.decode(v) do
      {:ok, list} when is_list(list) -> list
      _ -> nil
    end
  end

  defp parse_json_array(v) when is_list(v), do: v
  defp parse_json_array(_), do: nil

  defp p(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end
end
