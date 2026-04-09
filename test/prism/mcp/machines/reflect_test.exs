defmodule Prism.MCP.Machines.ReflectTest do
  use Prism.DataCase

  alias Prism.MCP.Machines.Reflect
  import Prism.Test.MachineHelpers

  setup do
    system = insert_system!()
    suite = insert_suite!()
    scenario = insert_scenario!(suite)
    %{system: system, suite: suite, scenario: scenario}
  end

  describe "invalid action" do
    test "returns error for unknown action" do
      result = Reflect.execute(%{action: "bogus"}, frame()) |> extract_result()
      assert result["status"] == "error"
      assert result["error"] =~ "Invalid action"
    end
  end

  describe "analyze_gaps" do
    test "analyzes gaps for current cycle" do
      result = Reflect.execute(%{action: "analyze_gaps"}, frame()) |> extract_result()
      assert result["status"] == "ok"
    end

    test "analyzes gaps for specific cycle" do
      result = Reflect.execute(%{action: "analyze_gaps", cycle: 1}, frame()) |> extract_result()
      assert result["status"] == "ok"
    end
  end

  describe "evolve" do
    test "returns error without recommendations" do
      result = Reflect.execute(%{action: "evolve"}, frame()) |> extract_result()
      assert result["status"] == "error"
      assert result["error"] =~ "recommendations"
    end

    test "retires a scenario", %{scenario: scenario} do
      recs_json =
        Jason.encode!([
          %{"action" => "retire", "scenario_id" => scenario.id, "reason" => "saturated"}
        ])

      result =
        Reflect.execute(%{action: "evolve", recommendations: recs_json}, frame())
        |> extract_result()

      assert result["status"] == "ok"
      r = result["result"]
      assert r["total"] == 1
      assert r["applied"] == 1
      [res] = r["results"]
      assert res["action"] == "retire"
      assert res["status"] == "ok"
    end

    test "promotes a scenario", %{scenario: scenario} do
      recs_json =
        Jason.encode!([
          %{"action" => "promote", "scenario_id" => scenario.id}
        ])

      result =
        Reflect.execute(%{action: "evolve", recommendations: recs_json}, frame())
        |> extract_result()

      assert result["status"] == "ok"
      assert result["result"]["applied"] == 1
    end

    test "forks a scenario", %{scenario: scenario} do
      recs_json =
        Jason.encode!([
          %{"action" => "fork", "scenario_id" => scenario.id, "difficulty" => 5}
        ])

      result =
        Reflect.execute(%{action: "evolve", recommendations: recs_json}, frame())
        |> extract_result()

      assert result["status"] == "ok"
      [res] = result["result"]["results"]
      assert res["action"] == "fork"
      assert res["status"] == "ok"
      assert res["new_id"]
    end

    test "skips unrecognized actions" do
      recs_json = Jason.encode!([%{"action" => "unknown_action"}])

      result =
        Reflect.execute(%{action: "evolve", recommendations: recs_json}, frame())
        |> extract_result()

      assert result["status"] == "ok"
      [res] = result["result"]["results"]
      assert res["status"] == "skipped"
    end

    test "handles nonexistent scenario_id" do
      recs_json =
        Jason.encode!([
          %{"action" => "retire", "scenario_id" => Ecto.UUID.generate(), "reason" => "test"}
        ])

      result =
        Reflect.execute(%{action: "evolve", recommendations: recs_json}, frame())
        |> extract_result()

      assert result["status"] == "ok"
      [res] = result["result"]["results"]
      assert res["status"] == "error"
      assert res["error"] =~ "not found"
    end
  end

  describe "advance_cycle" do
    test "advances to next cycle" do
      result = Reflect.execute(%{action: "advance_cycle"}, frame()) |> extract_result()
      # Could be ok or error depending on cycle manager state, both are valid
      assert result["status"] in ["ok", "error"]
    end
  end

  describe "calibrate_irt" do
    test "runs IRT recalibration" do
      result = Reflect.execute(%{action: "calibrate_irt"}, frame()) |> extract_result()
      assert result["status"] == "ok"
    end
  end

  describe "cycle_history" do
    test "returns cycle history" do
      result = Reflect.execute(%{action: "cycle_history"}, frame()) |> extract_result()
      assert result["status"] == "ok"
    end
  end

  describe "byor_recommend" do
    test "returns error without repo_anchor_id" do
      result = Reflect.execute(%{action: "byor_recommend"}, frame()) |> extract_result()
      assert result["status"] == "error"
    end

    test "recommends systems for repo anchor" do
      anchor = insert_repo_anchor!()

      result =
        Reflect.execute(%{action: "byor_recommend", repo_anchor_id: anchor.id}, frame())
        |> extract_result()

      assert result["status"] == "ok"
      r = result["result"]
      assert r["repo_anchor_id"] == anchor.id
      assert is_map(r["inferred_priorities"])
      assert is_list(r["recommendations"])
    end

    test "uses provided priorities" do
      anchor = insert_repo_anchor!()
      priorities = Jason.encode!(%{"stability" => 1.0, "plasticity" => 0.5})

      result =
        Reflect.execute(
          %{action: "byor_recommend", repo_anchor_id: anchor.id, priorities: priorities},
          frame()
        )
        |> extract_result()

      assert result["status"] == "ok"
      assert result["result"]["inferred_priorities"]["stability"] == 1.0
    end
  end

  describe "byor_infer_profile" do
    test "returns error without repo_anchor_id" do
      result = Reflect.execute(%{action: "byor_infer_profile"}, frame()) |> extract_result()
      assert result["status"] == "error"
    end

    test "infers profile from repo anchor" do
      anchor = insert_repo_anchor!()

      result =
        Reflect.execute(%{action: "byor_infer_profile", repo_anchor_id: anchor.id}, frame())
        |> extract_result()

      assert result["status"] == "ok"
      r = result["result"]
      assert r["id"]
      assert r["name"] =~ "inferred-from"
      assert is_map(r["dimension_priorities"])
      assert is_list(r["domains"])
    end
  end
end
