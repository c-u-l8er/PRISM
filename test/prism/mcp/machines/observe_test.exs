defmodule Prism.MCP.Machines.ObserveTest do
  use Prism.DataCase

  alias Prism.MCP.Machines.Observe
  import Prism.Test.MachineHelpers

  setup do
    system = insert_system!()
    suite = insert_suite!()
    scenario = insert_scenario!(suite)
    transcript = insert_transcript!(scenario, system)
    %{system: system, suite: suite, scenario: scenario, transcript: transcript}
  end

  describe "invalid action" do
    test "returns error for unknown action" do
      result = Observe.execute(%{action: "bogus"}, frame()) |> extract_result()
      assert result["status"] == "error"
      assert result["error"] =~ "Invalid action"
    end
  end

  describe "judge_transcript" do
    test "inserts judgments from JSON array", %{transcript: t} do
      judgments =
        Jason.encode!([
          %{
            "dimension" => "stability",
            "challenge_composite" => 0.8,
            "unprompted_score" => 0.6,
            "composite_score" => 0.74
          }
        ])

      result =
        Observe.execute(
          %{action: "judge_transcript", transcript_id: t.id, reason: judgments},
          frame()
        )
        |> extract_result()

      assert result["status"] == "ok"
      assert result["result"]["transcript_id"] == t.id
      [j] = result["result"]["judgments"]
      assert j["status"] == "ok"
      assert j["dimension"] == "stability"
    end

    test "returns error when transcript_id missing" do
      result =
        Observe.execute(%{action: "judge_transcript"}, frame())
        |> extract_result()

      assert result["status"] == "error"
    end
  end

  describe "judge_dimension" do
    test "inserts a single dimension judgment", %{transcript: t} do
      reason =
        Jason.encode!(%{
          "challenge_composite" => 0.9,
          "unprompted_score" => 0.7,
          "composite_score" => 0.83
        })

      result =
        Observe.execute(
          %{action: "judge_dimension", transcript_id: t.id, dimension: "plasticity", reason: reason},
          frame()
        )
        |> extract_result()

      assert result["status"] == "ok"
      assert result["result"]["dimension"] == "plasticity"
      assert result["result"]["composite_score"] == 0.83
    end

    test "rejects invalid dimension", %{transcript: t} do
      result =
        Observe.execute(
          %{action: "judge_dimension", transcript_id: t.id, dimension: "nonexistent"},
          frame()
        )
        |> extract_result()

      assert result["status"] == "error"
      assert result["error"] =~ "Invalid dimension"
    end

    test "returns error when transcript not found" do
      result =
        Observe.execute(
          %{action: "judge_dimension", transcript_id: Ecto.UUID.generate(), dimension: "stability"},
          frame()
        )
        |> extract_result()

      assert result["status"] == "error"
    end
  end

  describe "meta_judge" do
    test "inserts meta-judgment with cross-model check", %{transcript: t} do
      judgment = insert_judgment!(t, %{judge_model: "claude-sonnet"})

      reason =
        Jason.encode!(%{
          "consistency_score" => 0.9,
          "evidence_grounding_score" => 0.8,
          "rubric_compliance_score" => 0.85
        })

      result =
        Observe.execute(
          %{action: "meta_judge", judgment_id: judgment.id, meta_judge_model: "gpt-4o", reason: reason},
          frame()
        )
        |> extract_result()

      assert result["status"] == "ok"
      assert result["result"]["judgment_id"] == judgment.id
      assert result["result"]["recommendation"] in ["accept", "flag", "reject"]
    end

    test "rejects same model family", %{transcript: t} do
      judgment = insert_judgment!(t, %{judge_model: "claude-sonnet"})

      result =
        Observe.execute(
          %{action: "meta_judge", judgment_id: judgment.id, meta_judge_model: "claude-opus"},
          frame()
        )
        |> extract_result()

      assert result["status"] == "error"
      assert result["error"] =~ "different model family"
    end
  end

  describe "meta_judge_batch" do
    test "processes all judgments for a run", %{transcript: t, suite: suite, system: system} do
      run = insert_run!(suite, system)
      # Update transcript to belong to the run
      t |> Ecto.Changeset.change(%{run_id: run.id}) |> Repo.update!()
      _j1 = insert_judgment!(t, %{dimension: "stability", judge_model: "claude-sonnet"})
      _j2 = insert_judgment!(t, %{dimension: "plasticity", judge_model: "claude-sonnet"})

      result =
        Observe.execute(
          %{action: "meta_judge_batch", run_id: run.id, meta_judge_model: "gpt-4o"},
          frame()
        )
        |> extract_result()

      assert result["status"] == "ok"
      assert result["result"]["total"] == 2
      assert length(result["result"]["results"]) == 2
    end

    test "returns error when params missing" do
      result =
        Observe.execute(%{action: "meta_judge_batch"}, frame())
        |> extract_result()

      assert result["status"] == "error"
    end
  end

  describe "override" do
    test "overrides judgment score with audit trail", %{transcript: t} do
      judgment = insert_judgment!(t, %{composite_score: 0.3})

      result =
        Observe.execute(
          %{action: "override", judgment_id: judgment.id, new_score: 0.8, reason: "Manual correction after review"},
          frame()
        )
        |> extract_result()

      assert result["status"] == "ok"
      assert result["result"]["original_score"] == 0.3
      assert result["result"]["new_score"] == 0.8
      assert result["result"]["reason"] == "Manual correction after review"
    end

    test "returns error when params missing" do
      result =
        Observe.execute(%{action: "override"}, frame())
        |> extract_result()

      assert result["status"] == "error"
    end
  end
end
