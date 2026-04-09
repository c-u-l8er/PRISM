defmodule Prism.MCP.Machines.ComposeTest do
  use Prism.DataCase

  alias Prism.MCP.Machines.Compose
  import Prism.Test.MachineHelpers

  setup do
    suite = insert_suite!()
    scenario = insert_scenario!(suite)
    %{suite: suite, scenario: scenario}
  end

  describe "invalid action" do
    test "returns error for unknown action" do
      result = Compose.execute(%{action: "bogus"}, frame()) |> extract_result()
      assert result["status"] == "error"
      assert result["error"] =~ "Invalid action"
    end
  end

  describe "scenarios (store)" do
    test "stores scenarios from JSON array" do
      scenarios_json =
        Jason.encode!([
          %{
            "kind" => "frontier",
            "domain" => "code",
            "difficulty" => 3,
            "persona" => %{"name" => "dev"},
            "sessions" => [%{"turns" => []}],
            "cl_challenges" => %{"dimensions" => ["stability"]}
          }
        ])

      result =
        Compose.execute(%{action: "scenarios", scenario_ids: scenarios_json}, frame())
        |> extract_result()

      assert result["status"] == "ok"
      assert result["result"]["stored"] == 1
      assert result["result"]["failed"] == 0
      [sc] = result["result"]["scenarios"]
      assert sc["kind"] == "frontier"
      assert sc["domain"] == "code"
    end

    test "stores multiple scenarios" do
      scenarios_json =
        Jason.encode!([
          %{"kind" => "frontier", "domain" => "code", "difficulty" => 2,
            "persona" => %{}, "sessions" => [%{"turns" => []}], "cl_challenges" => %{}},
          %{"kind" => "frontier", "domain" => "knowledge", "difficulty" => 4,
            "persona" => %{}, "sessions" => [%{"turns" => []}], "cl_challenges" => %{}}
        ])

      result =
        Compose.execute(%{action: "scenarios", scenario_ids: scenarios_json}, frame())
        |> extract_result()

      assert result["status"] == "ok"
      assert result["result"]["stored"] == 2
    end

    test "returns error when scenario_ids is empty" do
      result =
        Compose.execute(%{action: "scenarios"}, frame())
        |> extract_result()

      assert result["status"] == "error"
      assert result["error"] =~ "scenario_ids required"
    end

    test "clamps difficulty to 1-5 range" do
      scenarios_json =
        Jason.encode!([
          %{"kind" => "frontier", "domain" => "code", "difficulty" => 99,
            "persona" => %{}, "sessions" => [%{"turns" => []}], "cl_challenges" => %{}}
        ])

      result =
        Compose.execute(%{action: "scenarios", scenario_ids: scenarios_json}, frame())
        |> extract_result()

      assert result["status"] == "ok"
      [sc] = result["result"]["scenarios"]
      # difficulty should be clamped to 5
      assert sc["status"] == "stored"
    end
  end

  describe "validate" do
    test "validates coverage of scenarios", %{scenario: scenario} do
      ids_json = Jason.encode!([scenario.id])

      result =
        Compose.execute(%{action: "validate", scenario_ids: ids_json}, frame())
        |> extract_result()

      assert result["status"] == "ok"
    end

    test "returns ok with empty list" do
      result =
        Compose.execute(%{action: "validate", scenario_ids: "[]"}, frame())
        |> extract_result()

      assert result["status"] == "ok"
    end
  end

  describe "list" do
    test "lists all scenarios", %{scenario: _scenario} do
      result = Compose.execute(%{action: "list"}, frame()) |> extract_result()
      assert result["status"] == "ok"
      assert is_list(result["result"])
    end

    test "filters by kind" do
      result = Compose.execute(%{action: "list", kind: "frontier"}, frame()) |> extract_result()
      assert result["status"] == "ok"
      Enum.each(result["result"], fn s -> assert s["kind"] == "frontier" end)
    end

    test "filters by domain" do
      result = Compose.execute(%{action: "list", domain: "code"}, frame()) |> extract_result()
      assert result["status"] == "ok"
    end
  end

  describe "get" do
    test "returns scenario by ID", %{scenario: scenario} do
      # Reload library so it picks up test-inserted scenario
      Prism.Scenario.Library.reload()

      result =
        Compose.execute(%{action: "get", scenario_id: scenario.id}, frame())
        |> extract_result()

      assert result["status"] == "ok"
      assert result["result"]["id"] == scenario.id
      assert result["result"]["kind"] == scenario.kind
    end

    test "returns error when scenario_id missing" do
      result = Compose.execute(%{action: "get"}, frame()) |> extract_result()
      assert result["status"] == "error"
      assert result["error"] =~ "scenario_id required"
    end

    test "returns error for nonexistent scenario" do
      result =
        Compose.execute(%{action: "get", scenario_id: Ecto.UUID.generate()}, frame())
        |> extract_result()

      assert result["status"] == "error"
      assert result["error"] =~ "not found"
    end
  end

  describe "retire" do
    test "retires a frontier scenario", %{scenario: scenario} do
      result =
        Compose.execute(
          %{action: "retire", scenario_id: scenario.id, reason: "saturated"},
          frame()
        )
        |> extract_result()

      assert result["status"] == "ok"
      assert result["result"]["retired"] == scenario.id
    end

    test "refuses to retire without reason", %{scenario: scenario} do
      result =
        Compose.execute(%{action: "retire", scenario_id: scenario.id}, frame())
        |> extract_result()

      assert result["status"] == "error"
    end

    test "refuses to retire anchor scenarios", %{suite: suite} do
      repo_anchor = insert_repo_anchor!()
      anchor = insert_scenario!(suite, %{kind: "anchor", repo_anchor_id: repo_anchor.id})

      result =
        Compose.execute(
          %{action: "retire", scenario_id: anchor.id, reason: "saturated"},
          frame()
        )
        |> extract_result()

      assert result["status"] == "error"
      assert result["error"] =~ "anchor"
    end
  end

  describe "byor_register" do
    test "returns error without repo_url" do
      result = Compose.execute(%{action: "byor_register"}, frame()) |> extract_result()
      assert result["status"] == "error"
      assert result["error"] =~ "repo_url required"
    end
  end

  describe "byor_discover" do
    test "returns error without repo_anchor_id" do
      result = Compose.execute(%{action: "byor_discover"}, frame()) |> extract_result()
      assert result["status"] == "error"
      assert result["error"] =~ "repo_anchor_id required"
    end

    test "returns error for nonexistent anchor" do
      result =
        Compose.execute(%{action: "byor_discover", repo_anchor_id: Ecto.UUID.generate()}, frame())
        |> extract_result()

      assert result["status"] == "error"
      assert result["error"] =~ "not found"
    end
  end
end
