defmodule Prism.Repo.Migrations.CreatePrismTablesSqlite do
  use Ecto.Migration

  @moduledoc """
  SQLite-compatible schema for PRISM.
  UUIDs are generated in Elixir (autogenerate: true on schemas).
  JSON columns stored as TEXT (SQLite has no jsonb).
  """

  def up do
    # ══════════════════════════════════════════════════════
    # Evaluation suites
    # ══════════════════════════════════════════════════════

    create table(:prism_suites, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :cycle_number, :integer, null: false
      add :simulator_model, :text, null: false
      add :cl_category_weights, :text, null: false
      add :total_scenarios, :integer, null: false
      add :anchor_count, :integer, null: false, default: 0
      add :frontier_count, :integer, null: false, default: 0
      add :validated_scenarios, :integer
      add :coverage_scores, :text
      add :status, :text, default: "draft"
      add :metadata, :text

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end

    create index(:prism_suites, [:cycle_number])
    create index(:prism_suites, [:status])

    # ══════════════════════════════════════════════════════
    # Git repo anchors (ground truth sources)
    # ══════════════════════════════════════════════════════

    create table(:prism_repo_anchors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :repo_url, :text, null: false
      add :license, :text, null: false
      add :commit_range_from, :text, null: false
      add :commit_range_to, :text, null: false
      add :total_commits, :integer, null: false
      add :clone_path, :text
      add :key_events, :text, null: false, default: "[]"
      add :snapshots, :text, null: false, default: "{}"

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end

    # ══════════════════════════════════════════════════════
    # Scenarios
    # ══════════════════════════════════════════════════════

    create table(:prism_scenarios, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :suite_id, references(:prism_suites, type: :binary_id, on_delete: :delete_all)
      add :kind, :text, null: false
      add :domain, :text, null: false
      add :repo_anchor_id, references(:prism_repo_anchors, type: :binary_id)
      add :difficulty, :integer, null: false
      add :persona, :text, null: false
      add :sessions, :text, null: false
      add :cl_challenges, :text, null: false

      # IRT parameters
      add :irt_difficulty_b, :float, default: 0.0
      add :irt_discrimination_a, :float, default: 1.0
      add :irt_guessing_c, :float, default: 0.1
      add :irt_calibrated, :boolean, default: false

      # Lifecycle
      add :validation_score, :float
      add :promoted_at, :utc_datetime_usec
      add :retired_at, :utc_datetime_usec
      add :retirement_reason, :text

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end

    create index(:prism_scenarios, [:suite_id])
    create index(:prism_scenarios, [:kind])
    create index(:prism_scenarios, [:domain])
    create index(:prism_scenarios, [:difficulty])

    # ══════════════════════════════════════════════════════
    # Scenario sequences (closed-loop testing)
    # ══════════════════════════════════════════════════════

    create table(:prism_sequences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :text, null: false
      add :description, :text
      add :scenario_ids, :text, null: false
      add :domain, :text, null: false
      add :pass_count, :integer, null: false, default: 3

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end

    # ══════════════════════════════════════════════════════
    # Registered memory systems
    # ══════════════════════════════════════════════════════

    create table(:prism_systems, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :text, null: false
      add :display_name, :text, null: false
      add :mcp_endpoint, :text, null: false
      add :transport, :text, null: false
      add :version, :text
      add :tool_count, :integer
      add :capabilities, :text

      add :registered_at, :utc_datetime_usec
      add :last_seen_at, :utc_datetime_usec
    end

    create unique_index(:prism_systems, [:name])

    # ══════════════════════════════════════════════════════
    # Execution tracking (runs)
    # ══════════════════════════════════════════════════════

    create table(:prism_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :suite_id, references(:prism_suites, type: :binary_id), null: false
      add :system_id, references(:prism_systems, type: :binary_id), null: false
      add :llm_backend, :text, null: false
      add :judge_models, :text, null: false, default: "{}"
      add :meta_judge_model, :text
      add :cycle_number, :integer, null: false
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :status, :text, default: "pending"
      add :aggregate_scores, :text
      add :weighted_total, :float
      add :loop_closure_rate, :float
      add :confidence_intervals, :text
      add :cost_usd, :float
      add :error_message, :text
      add :metadata, :text
    end

    create index(:prism_runs, [:suite_id])
    create index(:prism_runs, [:system_id])
    create index(:prism_runs, [:cycle_number])
    create index(:prism_runs, [:status])

    # ══════════════════════════════════════════════════════
    # Interaction transcripts
    # ══════════════════════════════════════════════════════

    create table(:prism_transcripts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :scenario_id, references(:prism_scenarios, type: :binary_id), null: false
      add :system_id, references(:prism_systems, type: :binary_id), null: false
      add :run_id, references(:prism_runs, type: :binary_id)
      add :llm_backend, :text, null: false
      add :sessions, :text, null: false
      add :total_tool_calls, :integer, default: 0
      add :total_turns, :integer, default: 0
      add :duration_ms, :integer
      add :cost_usd, :float

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end

    create index(:prism_transcripts, [:scenario_id])
    create index(:prism_transcripts, [:system_id])

    # ══════════════════════════════════════════════════════
    # Layer 2: Dimension judgments
    # ══════════════════════════════════════════════════════

    create table(:prism_judgments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :transcript_id, references(:prism_transcripts, type: :binary_id, on_delete: :delete_all),
        null: false
      add :dimension, :text, null: false
      add :judge_model, :text, null: false
      add :challenge_scores, :text, null: false, default: "[]"
      add :challenge_composite, :float, null: false
      add :unprompted_score, :float, default: 0.0
      add :unprompted_evidence, :text
      add :composite_score, :float, null: false
      add :rubric_version, :text, null: false
      add :raw_response, :text

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end

    create unique_index(:prism_judgments, [:transcript_id, :dimension])
    create index(:prism_judgments, [:transcript_id])
    create index(:prism_judgments, [:dimension])

    # ══════════════════════════════════════════════════════
    # Layer 3: Meta-judgments
    # ══════════════════════════════════════════════════════

    create table(:prism_meta_judgments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :judgment_id, references(:prism_judgments, type: :binary_id, on_delete: :delete_all),
        null: false
      add :meta_judge_model, :text, null: false
      add :consistency_score, :float, null: false
      add :evidence_grounding_score, :float, null: false
      add :rubric_compliance_score, :float, null: false
      add :composite_score, :float, null: false
      add :recommendation, :text, null: false
      add :reasoning, :text
      add :raw_response, :text

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end

    create unique_index(:prism_meta_judgments, [:judgment_id])
    create index(:prism_meta_judgments, [:recommendation])

    # ══════════════════════════════════════════════════════
    # Leaderboard
    # ══════════════════════════════════════════════════════

    create table(:prism_leaderboard, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :cycle_number, :integer, null: false
      add :system_id, references(:prism_systems, type: :binary_id), null: false
      add :system_name, :text, null: false
      add :llm_backend, :text, null: false
      add :domain, :text

      # 9 CL dimension scores
      add :stability_score, :float
      add :plasticity_score, :float
      add :knowledge_update_score, :float
      add :consolidation_score, :float
      add :temporal_score, :float
      add :transfer_score, :float
      add :uncertainty_score, :float
      add :forgetting_score, :float
      add :feedback_score, :float

      # Aggregate
      add :weighted_total, :float
      add :loop_closure_rate, :float

      # Meta-judge quality
      add :meta_judge_accept_rate, :float
      add :meta_judge_flag_rate, :float
      add :meta_judge_reject_rate, :float

      # Confidence
      add :confidence_intervals, :text

      # Provenance
      add :suite_id, references(:prism_suites, type: :binary_id)
      add :run_id, references(:prism_runs, type: :binary_id)

      add :computed_at, :utc_datetime_usec
    end

    create unique_index(:prism_leaderboard, [:cycle_number, :system_id, :llm_backend, :domain],
      name: :idx_leaderboard_unique_entry
    )

    create index(:prism_leaderboard, [:cycle_number])
    create index(:prism_leaderboard, [:system_id])

    # ══════════════════════════════════════════════════════
    # Cycle tracking
    # ══════════════════════════════════════════════════════

    create table(:prism_cycles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :cycle_number, :integer, null: false
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :suite_id, references(:prism_suites, type: :binary_id)
      add :anchor_count, :integer, default: 0
      add :frontier_count, :integer, default: 0
      add :prior_gap_analysis, :text
      add :irt_recalibration_summary, :text

      add :retired_scenario_count, :integer, default: 0
      add :promoted_scenario_count, :integer, default: 0
      add :new_scenario_count, :integer, default: 0
      add :forked_scenario_count, :integer, default: 0

      add :participating_systems, :integer
      add :participating_models, :integer
      add :top_system, :text
      add :top_weighted_total, :float
      add :metadata, :text
    end

    create unique_index(:prism_cycles, [:cycle_number])

    # ══════════════════════════════════════════════════════
    # Cycle feedback
    # ══════════════════════════════════════════════════════

    create table(:prism_cycle_feedback, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :from_cycle, :integer, null: false
      add :to_cycle, :integer, null: false
      add :gap_analysis, :text, null: false
      add :under_tested_dims, :text
      add :under_tested_domains, :text
      add :saturated_scenario_ids, :text
      add :too_hard_scenario_ids, :text
      add :low_variance_dims, :text
      add :promoted_scenario_ids, :text
      add :retired_scenario_ids, :text
      add :forked_scenario_ids, :text
      add :recommendations, :text

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end
  end

  def down do
    drop_if_exists table(:prism_cycle_feedback)
    drop_if_exists table(:prism_cycles)
    drop_if_exists table(:prism_leaderboard)
    drop_if_exists table(:prism_meta_judgments)
    drop_if_exists table(:prism_judgments)
    drop_if_exists table(:prism_transcripts)
    drop_if_exists table(:prism_runs)
    drop_if_exists table(:prism_systems)
    drop_if_exists table(:prism_sequences)
    drop_if_exists table(:prism_scenarios)
    drop_if_exists table(:prism_repo_anchors)
    drop_if_exists table(:prism_suites)
  end
end
