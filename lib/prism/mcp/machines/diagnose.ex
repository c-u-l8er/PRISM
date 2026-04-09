defmodule Prism.MCP.Machines.Diagnose do
  @moduledoc """
  Loop Phase 5: DIAGNOSE — "What's actionable?"

  The output phase: diagnostics, leaderboards, system comparison, task fit,
  and fix-and-retest verification. This is what makes PRISM a diagnostic tool
  rather than just a score generator.

  Actions:
  - `report`              — Full diagnostic (failures, fixes, regressions)
  - `failure_patterns`    — Clustered failure analysis per dimension
  - `retest`              — Re-run specific scenarios after a fix
  - `verify`              — Before/after comparison from retest
  - `regressions`         — Cross-cycle regression analysis
  - `suggest_fixes`       — AI-generated fix suggestions
  - `leaderboard`         — Rankings with domain filter
  - `leaderboard_history` — Scores over time
  - `compare_systems`     — Head-to-head across all 9 dimensions
  - `dimension_leaders`   — Top system per CL dimension
  - `fit_recommendation`  — System rec for a task profile
  - `compare_fit`         — Compare two systems for a specific task
  - `task_profiles`       — List pre-built and custom profiles

  Replaces: get_diagnostic_report, get_failure_patterns, run_retest,
            get_verification_report, get_regression_alerts, suggest_fixes,
            get_leaderboard, get_leaderboard_history, compare_systems,
            get_dimension_leaders, get_fit_recommendation, compare_fit,
            list_task_profiles
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  @valid_actions ~w(report failure_patterns retest verify regressions suggest_fixes leaderboard leaderboard_history compare_systems dimension_leaders fit_recommendation compare_fit task_profiles)

  schema do
    field(:action, :string,
      required: true,
      description:
        "Diagnostic action: report | failure_patterns | retest | verify | regressions | suggest_fixes | " <>
          "leaderboard | leaderboard_history | compare_systems | dimension_leaders | " <>
          "fit_recommendation | compare_fit | task_profiles"
    )

    # diagnostics
    field(:system_id, :string,
      description: "System ID (report, failure_patterns, regressions, suggest_fixes)"
    )

    field(:dimension, :string,
      description: "CL dimension (failure_patterns, suggest_fixes, leaderboard)"
    )

    field(:cycle, :number,
      description: "Cycle number (report, leaderboard, compare_systems, dimension_leaders)"
    )

    # retest
    field(:scenario_ids, :string, description: "JSON array of scenario UUIDs to retest (retest)")
    field(:version, :string, description: "System version label for retest (retest)")
    field(:retest_run_id, :string, description: "Retest run UUID (verify)")

    # regressions
    field(:from_cycle, :number, description: "Start cycle (regressions, leaderboard_history)")
    field(:to_cycle, :number, description: "End cycle (regressions, leaderboard_history)")

    # leaderboard
    field(:domain, :string,
      description: "Domain filter (leaderboard, leaderboard_history, compare_systems, dimension_leaders)"
    )

    field(:system, :string, description: "System filter (leaderboard, leaderboard_history)")
    field(:limit, :number, description: "Max results (leaderboard, default: 50)")

    # compare
    field(:system_a, :string, description: "First system (compare_systems, compare_fit)")
    field(:system_b, :string, description: "Second system (compare_systems, compare_fit)")

    # task fit
    field(:profile_id, :string, description: "Task profile UUID (fit_recommendation, compare_fit)")
    field(:budget, :string, description: "Budget constraint (fit_recommendation)")
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

  # -- Leaderboard actions (implemented) --

  defp dispatch("leaderboard", params, frame) do
    opts = [
      cycle: p(params, :cycle) && trunc(p(params, :cycle)),
      dimension: p(params, :dimension),
      domain: p(params, :domain),
      limit: (p(params, :limit) && trunc(p(params, :limit))) || 50
    ]

    result = Prism.Leaderboard.get(opts)
    {:reply, success_response(result), frame}
  end

  defp dispatch("leaderboard_history", params, frame) do
    case p(params, :system) do
      nil ->
        {:reply, error_response("system required for leaderboard_history"), frame}

      system ->
        opts = [
          from_cycle: p(params, :from_cycle) && trunc(p(params, :from_cycle)),
          to_cycle: p(params, :to_cycle) && trunc(p(params, :to_cycle)),
          domain: p(params, :domain)
        ]

        result = Prism.Leaderboard.history(system, opts)
        {:reply, success_response(result), frame}
    end
  end

  defp dispatch("compare_systems", params, frame) do
    with a when not is_nil(a) <- p(params, :system_a),
         b when not is_nil(b) <- p(params, :system_b) do
      opts = [
        cycle: p(params, :cycle) && trunc(p(params, :cycle)),
        domain: p(params, :domain)
      ]

      result = Prism.Leaderboard.compare(a, b, opts)
      {:reply, success_response(result), frame}
    else
      nil -> {:reply, error_response("system_a and system_b required"), frame}
    end
  end

  defp dispatch("dimension_leaders", params, frame) do
    opts = [
      cycle: p(params, :cycle) && trunc(p(params, :cycle)),
      domain: p(params, :domain)
    ]

    result = Prism.Leaderboard.dimension_leaders(opts)
    {:reply, success_response(result), frame}
  end

  # -- Diagnostic actions --

  defp dispatch("report", params, frame) do
    import Ecto.Query

    system_id = p(params, :system_id)
    cycle = p(params, :cycle) && trunc(p(params, :cycle))

    with system_id when not is_nil(system_id) <- system_id do
      # Gather all judgments for the system, optionally filtered by cycle
      judgments = query_judgments_for_system(system_id, cycle)

      # Aggregate by dimension
      by_dimension =
        judgments
        |> Enum.group_by(& &1.dimension)
        |> Enum.map(fn {dim, js} ->
          scores = Enum.map(js, & &1.composite_score)
          mean = if scores == [], do: 0.0, else: Enum.sum(scores) / length(scores)
          min = Enum.min(scores, fn -> 0.0 end)
          max = Enum.max(scores, fn -> 0.0 end)

          failures = Enum.filter(js, fn j -> j.composite_score < 0.5 end)

          {dim,
           %{
             mean: Float.round(mean, 4),
             min: Float.round(min, 4),
             max: Float.round(max, 4),
             count: length(js),
             failure_count: length(failures)
           }}
        end)
        |> Map.new()

      # Meta-judgment stats
      meta_judgments =
        from(m in Prism.MetaJudgment,
          join: j in Prism.Judgment,
          on: j.id == m.judgment_id,
          where: j.id in ^Enum.map(judgments, & &1.id),
          select: m
        )
        |> Prism.Repo.all()

      meta_stats =
        if meta_judgments == [] do
          %{total: 0}
        else
          accepts = Enum.count(meta_judgments, &(&1.recommendation == "accept"))
          flags = Enum.count(meta_judgments, &(&1.recommendation == "flag"))
          rejects = Enum.count(meta_judgments, &(&1.recommendation == "reject"))
          total = length(meta_judgments)

          %{
            total: total,
            accept_rate: Float.round(accepts / total, 4),
            flag_rate: Float.round(flags / total, 4),
            reject_rate: Float.round(rejects / total, 4)
          }
        end

      # Overall weighted total
      weights = Prism.Benchmark.CLCategories.default_weights()

      weighted_total =
        weights
        |> Enum.map(fn {dim_atom, weight} ->
          dim_str = Atom.to_string(dim_atom)

          case Map.get(by_dimension, dim_str) do
            nil -> 0.0
            %{mean: mean} -> mean * weight
          end
        end)
        |> Enum.sum()
        |> Float.round(4)

      result = %{
        system_id: system_id,
        cycle: cycle,
        total_judgments: length(judgments),
        weighted_total: weighted_total,
        dimensions: by_dimension,
        meta_judge_stats: meta_stats
      }

      {:reply, success_response(result), frame}
    else
      nil -> {:reply, error_response("system_id required"), frame}
    end
  end

  defp dispatch("failure_patterns", params, frame) do
    system_id = p(params, :system_id)
    dimension = p(params, :dimension)

    with system_id when not is_nil(system_id) <- system_id do
      judgments = query_judgments_for_system(system_id, nil)

      # Filter to failures (score < 0.5), optionally by dimension
      failures =
        judgments
        |> Enum.filter(fn j ->
          j.composite_score < 0.5 and (is_nil(dimension) or j.dimension == dimension)
        end)

      # Cluster failures by dimension
      by_dimension =
        failures
        |> Enum.group_by(& &1.dimension)
        |> Enum.map(fn {dim, js} ->
          scores = Enum.map(js, & &1.composite_score)
          mean = if scores == [], do: 0.0, else: Enum.sum(scores) / length(scores)

          # Extract common patterns from challenge_scores
          challenge_types =
            js
            |> Enum.flat_map(fn j ->
              (j.challenge_scores || [])
              |> Enum.filter(fn cs -> (Map.get(cs, "score") || 1.0) < 0.5 end)
              |> Enum.map(fn cs -> Map.get(cs, "type", "unknown") end)
            end)
            |> Enum.frequencies()
            |> Enum.sort_by(fn {_type, count} -> -count end)

          {dim,
           %{
             failure_count: length(js),
             mean_score: Float.round(mean, 4),
             common_challenge_types: challenge_types,
             judgment_ids: Enum.map(js, & &1.id)
           }}
        end)
        |> Map.new()

      result = %{
        system_id: system_id,
        total_failures: length(failures),
        patterns: by_dimension
      }

      {:reply, success_response(result), frame}
    else
      nil -> {:reply, error_response("system_id required"), frame}
    end
  end

  defp dispatch("retest", params, frame) do
    system_id = p(params, :system_id)
    scenario_ids_json = p(params, :scenario_ids)
    version = p(params, :version)
    llm_backend = p(params, :system) || "agent"

    with system_id when not is_nil(system_id) <- system_id,
         scenario_ids when is_list(scenario_ids) <- parse_json_array(scenario_ids_json) do
      # Create a run record for tracking
      run_attrs = %{
        suite_id: nil,
        system_id: system_id,
        llm_backend: llm_backend,
        cycle_number: 0,
        status: "interacting",
        metadata: %{"type" => "retest", "version" => version}
      }

      # Try to create a run, but proceed even without one
      run_id =
        case Prism.Repo.insert(Prism.Run.changeset(%Prism.Run{}, run_attrs)) do
          {:ok, run} -> run.id
          _ -> nil
        end

      results =
        Enum.map(scenario_ids, fn sid ->
          case Prism.Scenario.Library.get(sid) do
            nil ->
              %{scenario_id: sid, status: "error", error: "scenario not found"}

            scenario ->
              case Prism.Simulator.Engine.interact(scenario, %{}, system_id, llm_backend) do
                {:ok, result} ->
                  transcript_attrs = %{
                    scenario_id: sid,
                    system_id: system_id,
                    run_id: run_id,
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

                  %{scenario_id: sid, status: "ok", transcript_id: tid}

                {:error, reason} ->
                  %{scenario_id: sid, status: "error", error: inspect(reason)}
              end
          end
        end)

      # Mark run as completed
      if run_id do
        case Prism.Repo.get(Prism.Run, run_id) do
          nil -> :ok
          run -> Prism.Repo.update(Prism.Run.status_changeset(run, "completed"))
        end
      end

      {:reply,
       success_response(%{
         run_id: run_id,
         version: version,
         total: length(results),
         successes: Enum.count(results, &(&1.status == "ok")),
         results: results
       }), frame}
    else
      nil -> {:reply, error_response("system_id and scenario_ids (JSON array) required"), frame}
      _ -> {:reply, error_response("scenario_ids must be a JSON array"), frame}
    end
  end

  defp dispatch("verify", params, frame) do
    import Ecto.Query

    retest_run_id = p(params, :retest_run_id)
    system_id = p(params, :system_id)

    with retest_run_id when not is_nil(retest_run_id) <- retest_run_id do
      # Get judgments from the retest run
      retest_judgments =
        from(j in Prism.Judgment,
          join: t in Prism.Transcript,
          on: t.id == j.transcript_id,
          where: t.run_id == ^retest_run_id,
          select: j
        )
        |> Prism.Repo.all()

      # Get prior judgments for comparison (same system, same scenarios, earlier runs)
      retest_scenarios =
        from(t in Prism.Transcript,
          where: t.run_id == ^retest_run_id,
          select: t.scenario_id
        )
        |> Prism.Repo.all()

      prior_judgments =
        if system_id && retest_scenarios != [] do
          from(j in Prism.Judgment,
            join: t in Prism.Transcript,
            on: t.id == j.transcript_id,
            where:
              t.system_id == ^system_id and
                t.scenario_id in ^retest_scenarios and
                t.run_id != ^retest_run_id,
            order_by: [desc: j.created_at],
            select: j
          )
          |> Prism.Repo.all()
        else
          []
        end

      # Compare by dimension
      retest_by_dim =
        retest_judgments
        |> Enum.group_by(& &1.dimension)
        |> Enum.map(fn {dim, js} ->
          scores = Enum.map(js, & &1.composite_score)
          {dim, Enum.sum(scores) / max(length(scores), 1)}
        end)
        |> Map.new()

      prior_by_dim =
        prior_judgments
        |> Enum.group_by(& &1.dimension)
        |> Enum.map(fn {dim, js} ->
          scores = Enum.map(js, & &1.composite_score)
          {dim, Enum.sum(scores) / max(length(scores), 1)}
        end)
        |> Map.new()

      comparisons =
        Enum.map(retest_by_dim, fn {dim, retest_score} ->
          prior_score = Map.get(prior_by_dim, dim)
          delta = if prior_score, do: Float.round(retest_score - prior_score, 4), else: nil
          improved = if delta, do: delta > 0.0, else: nil

          %{
            dimension: dim,
            prior_score: prior_score && Float.round(prior_score, 4),
            retest_score: Float.round(retest_score, 4),
            delta: delta,
            improved: improved
          }
        end)

      overall_improved = Enum.all?(comparisons, fn c -> c.improved == true or c.improved == nil end)

      {:reply,
       success_response(%{
         retest_run_id: retest_run_id,
         comparisons: comparisons,
         overall_improved: overall_improved
       }), frame}
    else
      nil -> {:reply, error_response("retest_run_id required"), frame}
    end
  end

  defp dispatch("regressions", params, frame) do
    import Ecto.Query

    system_id = p(params, :system_id)
    from_cycle = p(params, :from_cycle) && trunc(p(params, :from_cycle))
    to_cycle = p(params, :to_cycle) && trunc(p(params, :to_cycle))

    with system_id when not is_nil(system_id) <- system_id,
         from_c when not is_nil(from_c) <- from_cycle,
         to_c when not is_nil(to_c) <- to_cycle do
      # Get judgments grouped by cycle and dimension
      judgments =
        from(j in Prism.Judgment,
          join: t in Prism.Transcript,
          on: t.id == j.transcript_id,
          join: r in Prism.Run,
          on: r.id == t.run_id,
          where:
            t.system_id == ^system_id and
              r.cycle_number >= ^from_c and
              r.cycle_number <= ^to_c,
          select: %{
            dimension: j.dimension,
            score: j.composite_score,
            cycle: r.cycle_number
          }
        )
        |> Prism.Repo.all()

      # Group by dimension, then by cycle
      by_dim_cycle =
        judgments
        |> Enum.group_by(& &1.dimension)
        |> Enum.map(fn {dim, js} ->
          by_cycle =
            js
            |> Enum.group_by(& &1.cycle)
            |> Enum.sort_by(fn {c, _} -> c end)
            |> Enum.map(fn {c, cycle_js} ->
              scores = Enum.map(cycle_js, & &1.score)
              mean = Enum.sum(scores) / max(length(scores), 1)
              {c, Float.round(mean, 4)}
            end)

          # Detect regressions (score drops > 0.05 between consecutive cycles)
          regressions =
            by_cycle
            |> Enum.chunk_every(2, 1, :discard)
            |> Enum.filter(fn [{_c1, s1}, {_c2, s2}] -> s1 - s2 > 0.05 end)
            |> Enum.map(fn [{c1, s1}, {c2, s2}] ->
              %{from_cycle: c1, to_cycle: c2, from_score: s1, to_score: s2, drop: Float.round(s1 - s2, 4)}
            end)

          {dim, %{scores_by_cycle: Map.new(by_cycle), regressions: regressions}}
        end)
        |> Map.new()

      all_regressions =
        by_dim_cycle
        |> Enum.flat_map(fn {dim, %{regressions: regs}} ->
          Enum.map(regs, &Map.put(&1, :dimension, dim))
        end)

      {:reply,
       success_response(%{
         system_id: system_id,
         from_cycle: from_c,
         to_cycle: to_c,
         dimensions: by_dim_cycle,
         total_regressions: length(all_regressions),
         regressions: all_regressions
       }), frame}
    else
      nil -> {:reply, error_response("system_id, from_cycle, and to_cycle required"), frame}
    end
  end

  defp dispatch("suggest_fixes", params, frame) do
    system_id = p(params, :system_id)
    dimension = p(params, :dimension)

    with system_id when not is_nil(system_id) <- system_id do
      judgments = query_judgments_for_system(system_id, nil)

      failures =
        judgments
        |> Enum.filter(fn j ->
          j.composite_score < 0.5 and (is_nil(dimension) or j.dimension == dimension)
        end)

      # Generate structured fix suggestions based on failure patterns
      suggestions =
        failures
        |> Enum.group_by(& &1.dimension)
        |> Enum.map(fn {dim, js} ->
          scores = Enum.map(js, & &1.composite_score)
          mean = Enum.sum(scores) / max(length(scores), 1)

          # Analyze challenge types that failed
          failed_types =
            js
            |> Enum.flat_map(fn j ->
              (j.challenge_scores || [])
              |> Enum.filter(fn cs -> (Map.get(cs, "score") || 1.0) < 0.5 end)
              |> Enum.map(fn cs -> Map.get(cs, "type", "unknown") end)
            end)
            |> Enum.frequencies()

          # Low unprompted scores indicate the system doesn't surface context proactively
          low_unprompted = Enum.count(js, fn j -> (j.unprompted_score || 0.0) < 0.3 end)

          fixes =
            []
            |> maybe_add_fix(mean < 0.3, %{
              priority: "high",
              fix: "Seed procedural/semantic nodes covering #{dim} vocabulary and concepts",
              rationale: "Mean score #{Float.round(mean, 2)} suggests missing knowledge, not retrieval failure"
            })
            |> maybe_add_fix(low_unprompted > length(js) / 2, %{
              priority: "medium",
              fix: "Improve retrieval ranking to surface #{dim}-related context proactively",
              rationale: "#{low_unprompted}/#{length(js)} judgments have low unprompted scores"
            })
            |> maybe_add_fix(map_size(failed_types) > 0, %{
              priority: "medium",
              fix: "Address failing challenge types: #{inspect(Map.keys(failed_types))}",
              rationale: "Specific challenge patterns consistently fail"
            })

          %{dimension: dim, failure_count: length(js), mean_score: Float.round(mean, 4), fixes: fixes}
        end)

      {:reply,
       success_response(%{system_id: system_id, suggestions: suggestions}), frame}
    else
      nil -> {:reply, error_response("system_id required"), frame}
    end
  end

  # -- Task fit actions --

  defp dispatch("fit_recommendation", params, frame) do
    profile_id = p(params, :profile_id)

    with profile_id when not is_nil(profile_id) <- profile_id,
         [{^profile_id, profile}] <- :ets.lookup(:prism_task_profiles, profile_id) do
      # Get all leaderboard entries
      entries = Prism.Leaderboard.get([])

      # Score each system against the profile priorities
      scored =
        Enum.map(entries, fn entry ->
          fit_score = compute_fit_score(entry, profile)
          %{system: entry[:system_name], weighted_total: entry[:weighted_total], fit_score: fit_score}
        end)
        |> Enum.sort_by(& &1.fit_score, :desc)

      {:reply,
       success_response(%{
         profile_id: profile_id,
         profile_name: profile.name,
         recommendations: scored
       }), frame}
    else
      nil -> {:reply, error_response("profile_id required"), frame}
      [] -> {:reply, error_response("profile not found: #{profile_id}"), frame}
    end
  end

  defp dispatch("compare_fit", params, frame) do
    profile_id = p(params, :profile_id)
    system_a = p(params, :system_a)
    system_b = p(params, :system_b)

    with profile_id when not is_nil(profile_id) <- profile_id,
         system_a when not is_nil(system_a) <- system_a,
         system_b when not is_nil(system_b) <- system_b,
         [{^profile_id, profile}] <- :ets.lookup(:prism_task_profiles, profile_id) do
      # Get leaderboard entries for both systems
      all_entries = Prism.Leaderboard.get([])

      entry_a = Enum.find(all_entries, fn e -> e[:system_name] == system_a end)
      entry_b = Enum.find(all_entries, fn e -> e[:system_name] == system_b end)

      score_a = if entry_a, do: compute_fit_score(entry_a, profile), else: 0.0
      score_b = if entry_b, do: compute_fit_score(entry_b, profile), else: 0.0

      winner =
        cond do
          score_a > score_b + 0.05 -> system_a
          score_b > score_a + 0.05 -> system_b
          true -> "tied"
        end

      {:reply,
       success_response(%{
         profile_id: profile_id,
         system_a: %{name: system_a, fit_score: score_a},
         system_b: %{name: system_b, fit_score: score_b},
         winner: winner
       }), frame}
    else
      nil -> {:reply, error_response("profile_id, system_a, and system_b required"), frame}
      [] -> {:reply, error_response("profile not found"), frame}
    end
  end

  defp dispatch("task_profiles", _params, frame) do
    profiles =
      :ets.tab2list(:prism_task_profiles)
      |> Enum.map(fn {_id, profile} -> profile end)

    {:reply, success_response(%{profiles: profiles, total: length(profiles)}), frame}
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

  defp maybe_add_fix(fixes, true, fix), do: fixes ++ [fix]
  defp maybe_add_fix(fixes, false, _fix), do: fixes

  defp compute_fit_score(entry, profile) do
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

    priorities = profile.dimension_priorities || %{}

    if map_size(priorities) == 0 do
      entry[:weighted_total] || 0.0
    else
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

  defp query_judgments_for_system(system_id, cycle) do
    import Ecto.Query

    base =
      from(j in Prism.Judgment,
        join: t in Prism.Transcript,
        on: t.id == j.transcript_id,
        where: t.system_id == ^system_id,
        select: j
      )

    query =
      case cycle do
        nil ->
          base

        c ->
          from([j, t] in base,
            join: r in Prism.Run,
            on: r.id == t.run_id,
            where: r.cycle_number == ^c
          )
      end

    Prism.Repo.all(query)
  end

  defp p(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end
end
