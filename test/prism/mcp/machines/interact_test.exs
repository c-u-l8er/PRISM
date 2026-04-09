defmodule Prism.MCP.Machines.InteractTest do
  use Prism.DataCase

  alias Prism.MCP.Machines.Interact
  import Prism.Test.MachineHelpers

  setup do
    system = insert_system!()
    suite = insert_suite!()
    scenario = insert_scenario!(suite)
    run = insert_run!(suite, system)
    transcript = insert_transcript!(scenario, system, %{run_id: run.id})

    %{system: system, suite: suite, scenario: scenario, run: run, transcript: transcript}
  end

  describe "invalid action" do
    test "returns error for unknown action" do
      result = Interact.execute(%{action: "bogus"}, frame()) |> extract_result()
      assert result["status"] == "error"
      assert result["error"] =~ "Invalid action"
    end
  end

  describe "run" do
    test "returns error without required params" do
      result = Interact.execute(%{action: "run"}, frame()) |> extract_result()
      assert result["status"] == "error"
      assert result["error"] =~ "scenario_id"
    end

    test "runs a scenario against a system", %{scenario: scenario, system: system} do
      # Reload library so it picks up test-inserted scenario
      Prism.Scenario.Library.reload()

      result =
        Interact.execute(
          %{
            action: "run",
            scenario_id: scenario.id,
            system_id: system.id,
            llm_backend: "test-model"
          },
          frame()
        )
        |> extract_result()

      assert result["status"] == "ok"
      r = result["result"]
      assert r["transcript_id"]
      assert r["total_turns"] >= 0
    end
  end

  describe "run_sequence" do
    test "returns error without required params" do
      result = Interact.execute(%{action: "run_sequence"}, frame()) |> extract_result()
      assert result["status"] == "error"
    end
  end

  describe "run_matrix" do
    test "returns error without systems/models arrays" do
      result = Interact.execute(%{action: "run_matrix"}, frame()) |> extract_result()
      assert result["status"] == "error"
      assert result["error"] =~ "JSON arrays"
    end

    test "runs matrix of systems × models", %{system: system} do
      # Reload library so it picks up test-inserted scenarios
      Prism.Scenario.Library.reload()

      systems_json = Jason.encode!([system.id])
      models_json = Jason.encode!(["test-model"])

      result =
        Interact.execute(
          %{action: "run_matrix", systems: systems_json, models: models_json},
          frame()
        )
        |> extract_result()

      assert result["status"] == "ok"
      r = result["result"]
      assert r["systems"] == 1
      assert r["models"] == 1
      assert r["total"] >= 0
    end
  end

  describe "status" do
    test "returns error without run_id" do
      result = Interact.execute(%{action: "status"}, frame()) |> extract_result()
      assert result["status"] == "error"
      assert result["error"] =~ "run_id required"
    end

    test "returns status of a run", %{run: run} do
      result =
        Interact.execute(%{action: "status", run_id: run.id}, frame())
        |> extract_result()

      assert result["status"] == "ok"
      assert result["result"]["status"] == "completed"
    end

    test "returns error for nonexistent run" do
      result =
        Interact.execute(%{action: "status", run_id: Ecto.UUID.generate()}, frame())
        |> extract_result()

      assert result["status"] == "error"
      assert result["error"] =~ "not found"
    end
  end

  describe "transcript" do
    test "returns error without transcript_id" do
      result = Interact.execute(%{action: "transcript"}, frame()) |> extract_result()
      assert result["status"] == "error"
      assert result["error"] =~ "transcript_id required"
    end

    test "returns transcript by ID", %{transcript: transcript} do
      result =
        Interact.execute(%{action: "transcript", transcript_id: transcript.id}, frame())
        |> extract_result()

      assert result["status"] == "ok"
    end

    test "returns error for nonexistent transcript" do
      result =
        Interact.execute(%{action: "transcript", transcript_id: Ecto.UUID.generate()}, frame())
        |> extract_result()

      assert result["status"] == "error"
      assert result["error"] =~ "not found"
    end
  end

  describe "cancel" do
    test "returns error without run_id" do
      result = Interact.execute(%{action: "cancel"}, frame()) |> extract_result()
      assert result["status"] == "error"
      assert result["error"] =~ "run_id required"
    end

    test "cancels an in-progress run", %{suite: suite, system: system} do
      run = insert_run!(suite, system, %{status: "interacting"})

      result =
        Interact.execute(%{action: "cancel", run_id: run.id}, frame())
        |> extract_result()

      assert result["status"] == "ok"
      assert result["result"]["status"] == "cancelled"
    end
  end

  describe "byor_evaluate" do
    test "returns error without required params" do
      result = Interact.execute(%{action: "byor_evaluate"}, frame()) |> extract_result()
      assert result["status"] == "error"
    end

    test "returns error when no scenarios for anchor", %{system: system} do
      anchor = insert_repo_anchor!()

      result =
        Interact.execute(
          %{action: "byor_evaluate", system_id: system.id, repo_anchor_id: anchor.id},
          frame()
        )
        |> extract_result()

      assert result["status"] == "error"
      assert result["error"] =~ "No active scenarios"
    end

    test "evaluates scenarios linked to repo anchor", %{system: system, suite: suite} do
      anchor = insert_repo_anchor!()
      _scenario = insert_scenario!(suite, %{repo_anchor_id: anchor.id})

      result =
        Interact.execute(
          %{action: "byor_evaluate", system_id: system.id, repo_anchor_id: anchor.id},
          frame()
        )
        |> extract_result()

      assert result["status"] == "ok"
      r = result["result"]
      assert r["system_id"] == system.id
      assert r["total"] == 1
    end
  end

  describe "byor_compare" do
    test "returns error without required params" do
      result = Interact.execute(%{action: "byor_compare"}, frame()) |> extract_result()
      assert result["status"] == "error"
    end

    test "compares two systems on repo anchor", %{suite: suite} do
      system_a = insert_system!()
      system_b = insert_system!()
      anchor = insert_repo_anchor!()
      _scenario = insert_scenario!(suite, %{repo_anchor_id: anchor.id})

      result =
        Interact.execute(
          %{
            action: "byor_compare",
            system_a: system_a.id,
            system_b: system_b.id,
            repo_anchor_id: anchor.id
          },
          frame()
        )
        |> extract_result()

      assert result["status"] == "ok"
      r = result["result"]
      assert r["system_a"]["id"] == system_a.id
      assert r["system_b"]["id"] == system_b.id
    end
  end
end
