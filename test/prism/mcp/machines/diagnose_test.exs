defmodule Prism.MCP.Machines.DiagnoseTest do
  use Prism.DataCase

  alias Prism.MCP.Machines.Diagnose
  import Prism.Test.MachineHelpers

  setup do
    system = insert_system!()
    suite = insert_suite!()
    scenario = insert_scenario!(suite)
    run = insert_run!(suite, system)
    transcript = insert_transcript!(scenario, system, %{run_id: run.id})

    # Insert judgments with varying scores
    _j_stability = insert_judgment!(transcript, %{dimension: "stability", composite_score: 0.8})
    _j_plasticity = insert_judgment!(transcript, %{dimension: "plasticity", composite_score: 0.3})
    _j_transfer = insert_judgment!(transcript, %{dimension: "transfer", composite_score: 0.9})

    %{system: system, suite: suite, scenario: scenario, run: run, transcript: transcript}
  end

  describe "invalid action" do
    test "returns error" do
      result = Diagnose.execute(%{action: "fake"}, frame()) |> extract_result()
      assert result["status"] == "error"
    end
  end

  describe "leaderboard" do
    test "returns empty list when no data" do
      result = Diagnose.execute(%{action: "leaderboard"}, frame()) |> extract_result()
      assert result["status"] == "ok"
    end
  end

  describe "leaderboard_history" do
    test "requires system param" do
      result = Diagnose.execute(%{action: "leaderboard_history"}, frame()) |> extract_result()
      assert result["status"] == "error"
    end

    test "returns history for system" do
      result =
        Diagnose.execute(%{action: "leaderboard_history", system: "test"}, frame())
        |> extract_result()

      assert result["status"] == "ok"
    end
  end

  describe "compare_systems" do
    test "requires both systems" do
      result = Diagnose.execute(%{action: "compare_systems"}, frame()) |> extract_result()
      assert result["status"] == "error"
    end

    test "compares two systems" do
      result =
        Diagnose.execute(%{action: "compare_systems", system_a: "a", system_b: "b"}, frame())
        |> extract_result()

      assert result["status"] == "ok"
    end
  end

  describe "dimension_leaders" do
    test "returns all dimensions" do
      result = Diagnose.execute(%{action: "dimension_leaders"}, frame()) |> extract_result()
      assert result["status"] == "ok"
    end
  end

  describe "report" do
    test "aggregates judgments by dimension", %{system: system} do
      result =
        Diagnose.execute(%{action: "report", system_id: system.id}, frame())
        |> extract_result()

      assert result["status"] == "ok"
      r = result["result"]
      assert r["system_id"] == system.id
      assert r["total_judgments"] == 3
      assert is_map(r["dimensions"])
      assert r["dimensions"]["stability"]["count"] == 1
      assert r["dimensions"]["plasticity"]["failure_count"] == 1
    end

    test "returns error without system_id" do
      result = Diagnose.execute(%{action: "report"}, frame()) |> extract_result()
      assert result["status"] == "error"
    end
  end

  describe "failure_patterns" do
    test "clusters failures by dimension", %{system: system} do
      result =
        Diagnose.execute(%{action: "failure_patterns", system_id: system.id}, frame())
        |> extract_result()

      assert result["status"] == "ok"
      r = result["result"]
      assert r["total_failures"] == 1
      assert Map.has_key?(r["patterns"], "plasticity")
    end

    test "filters by dimension", %{system: system} do
      result =
        Diagnose.execute(
          %{action: "failure_patterns", system_id: system.id, dimension: "stability"},
          frame()
        )
        |> extract_result()

      assert result["status"] == "ok"
      # stability scored 0.8, not a failure
      assert result["result"]["total_failures"] == 0
    end
  end

  describe "retest" do
    test "requires system_id and scenario_ids" do
      result = Diagnose.execute(%{action: "retest"}, frame()) |> extract_result()
      assert result["status"] == "error"
    end
  end

  describe "verify" do
    test "requires retest_run_id" do
      result = Diagnose.execute(%{action: "verify"}, frame()) |> extract_result()
      assert result["status"] == "error"
    end

    test "returns comparisons for a run", %{run: run, system: system} do
      result =
        Diagnose.execute(
          %{action: "verify", retest_run_id: run.id, system_id: system.id},
          frame()
        )
        |> extract_result()

      assert result["status"] == "ok"
      r = result["result"]
      assert r["retest_run_id"] == run.id
      assert is_list(r["comparisons"])
    end
  end

  describe "regressions" do
    test "requires system_id, from_cycle, to_cycle" do
      result = Diagnose.execute(%{action: "regressions"}, frame()) |> extract_result()
      assert result["status"] == "error"
    end

    test "detects regressions across cycles", %{system: system} do
      result =
        Diagnose.execute(
          %{action: "regressions", system_id: system.id, from_cycle: 1, to_cycle: 3},
          frame()
        )
        |> extract_result()

      assert result["status"] == "ok"
      r = result["result"]
      assert r["system_id"] == system.id
      assert is_map(r["dimensions"])
    end
  end

  describe "suggest_fixes" do
    test "generates suggestions based on failures", %{system: system} do
      result =
        Diagnose.execute(%{action: "suggest_fixes", system_id: system.id}, frame())
        |> extract_result()

      assert result["status"] == "ok"
      r = result["result"]
      assert is_list(r["suggestions"])
      # plasticity scored 0.3, should have suggestions
      plasticity_fix = Enum.find(r["suggestions"], &(&1["dimension"] == "plasticity"))
      assert plasticity_fix
      assert plasticity_fix["failure_count"] == 1
      # fixes may be empty when no LLM is available (PRISM is a pure data layer)
      assert is_list(plasticity_fix["fixes"])
    end
  end

  describe "fit_recommendation" do
    test "requires profile_id" do
      result = Diagnose.execute(%{action: "fit_recommendation"}, frame()) |> extract_result()
      assert result["status"] == "error"
    end

    test "returns error for nonexistent profile" do
      result =
        Diagnose.execute(%{action: "fit_recommendation", profile_id: Ecto.UUID.generate()}, frame())
        |> extract_result()

      assert result["status"] == "error"
      assert result["error"] =~ "not found"
    end
  end

  describe "compare_fit" do
    test "requires all params" do
      result = Diagnose.execute(%{action: "compare_fit"}, frame()) |> extract_result()
      assert result["status"] == "error"
    end
  end

  describe "task_profiles" do
    test "lists profiles from ETS" do
      result = Diagnose.execute(%{action: "task_profiles"}, frame()) |> extract_result()
      assert result["status"] == "ok"
      assert is_list(result["result"]["profiles"])
    end
  end
end
