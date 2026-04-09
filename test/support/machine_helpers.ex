defmodule Prism.Test.MachineHelpers do
  @moduledoc """
  Shared helpers for machine tests.
  """

  alias Prism.Repo

  @frame %Anubis.Server.Frame{}

  def frame, do: @frame

  def extract_result({:reply, response, _frame}) do
    case response do
      %{content: [%{text: json}]} ->
        Jason.decode!(json)

      %{content: [%{"text" => json}]} ->
        Jason.decode!(json)

      %Anubis.Server.Response{content: [%{"text" => json}]} ->
        Jason.decode!(json)

      %Anubis.Server.Response{content: [%{text: json}]} ->
        Jason.decode!(json)

      other ->
        other
    end
  end

  def insert_system!(attrs \\ %{}) do
    defaults = %{
      name: "test-system-#{System.unique_integer([:positive])}",
      display_name: "Test System",
      mcp_endpoint: "stdio://test",
      transport: "stdio"
    }

    %Prism.System{}
    |> Prism.System.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_suite!(attrs \\ %{}) do
    defaults = %{
      cycle_number: 1,
      simulator_model: "test-model",
      cl_category_weights: Prism.Benchmark.CLCategories.default_weights() |> Jason.encode!() |> Jason.decode!(),
      total_scenarios: 1
    }

    %Prism.Suite{}
    |> Prism.Suite.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_repo_anchor!(attrs \\ %{}) do
    defaults = %{
      repo_url: "https://github.com/test/repo",
      license: "MIT",
      commit_range_from: "abc123",
      commit_range_to: "def456",
      total_commits: 100,
      key_events: [
        %{
          "cl_dimensions" => ["stability", "plasticity"],
          "domains" => ["code"]
        }
      ]
    }

    %Prism.RepoAnchor{}
    |> Prism.RepoAnchor.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_scenario!(suite, attrs \\ %{}) do
    defaults = %{
      kind: "frontier",
      domain: "code",
      difficulty: 3,
      persona: %{"name" => "test-user", "expertise" => "intermediate"},
      sessions: [%{"turns" => []}],
      cl_challenges: %{"dimensions" => ["stability", "plasticity"]},
      suite_id: suite.id
    }

    %Prism.Scenario{}
    |> Prism.Scenario.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_run!(suite, system, attrs \\ %{}) do
    defaults = %{
      suite_id: suite.id,
      system_id: system.id,
      llm_backend: "test-model",
      cycle_number: 1,
      status: "completed"
    }

    %Prism.Run{}
    |> Prism.Run.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_transcript!(scenario, system, attrs \\ %{}) do
    defaults = %{
      scenario_id: scenario.id,
      system_id: system.id,
      llm_backend: "test-model",
      sessions: [%{"turns" => [%{"query" => "test", "response" => "ok"}]}],
      total_turns: 1,
      total_tool_calls: 0,
      duration_ms: 100
    }

    %Prism.Transcript{}
    |> Prism.Transcript.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_judgment!(transcript, attrs \\ %{}) do
    defaults = %{
      transcript_id: transcript.id,
      dimension: "stability",
      judge_model: "claude-sonnet",
      challenge_scores: [],
      challenge_composite: 0.8,
      unprompted_score: 0.6,
      composite_score: 0.74,
      rubric_version: "prism-v3.0-cycle1"
    }

    %Prism.Judgment{}
    |> Prism.Judgment.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_meta_judgment!(judgment, attrs \\ %{}) do
    defaults = %{
      judgment_id: judgment.id,
      meta_judge_model: "gpt-4o",
      consistency_score: 0.8,
      evidence_grounding_score: 0.7,
      rubric_compliance_score: 0.9,
      composite_score: 0.8,
      recommendation: "accept"
    }

    %Prism.MetaJudgment{}
    |> Prism.MetaJudgment.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
