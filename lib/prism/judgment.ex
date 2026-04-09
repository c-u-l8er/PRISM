defmodule Prism.Judgment do
  @moduledoc """
  Ecto schema for Layer 2 dimension judgments.

  Each judgment evaluates one CL dimension for one transcript.
  Scores combine challenge scores (70% weight) with unprompted
  behavior scores (30% weight).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_dimensions ~w(
    stability plasticity knowledge_update temporal consolidation
    epistemic_awareness transfer forgetting feedback
  )

  schema "prism_judgments" do
    field(:dimension, :string)
    field(:judge_model, :string)
    field(:challenge_scores, {:array, :map}, default: [])
    field(:challenge_composite, :float)
    field(:unprompted_score, :float, default: 0.0)
    field(:unprompted_evidence, :string)
    field(:composite_score, :float)
    field(:rubric_version, :string)
    field(:raw_response, :map)

    belongs_to(:transcript, Prism.Transcript)
    has_one(:meta_judgment, Prism.MetaJudgment, foreign_key: :judgment_id)

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end

  @doc "Changeset for creating a new judgment."
  def changeset(judgment, attrs) do
    judgment
    |> cast(attrs, [
      :transcript_id,
      :dimension,
      :judge_model,
      :challenge_scores,
      :challenge_composite,
      :unprompted_score,
      :unprompted_evidence,
      :composite_score,
      :rubric_version,
      :raw_response
    ])
    |> validate_required([
      :transcript_id,
      :dimension,
      :judge_model,
      :challenge_composite,
      :composite_score,
      :rubric_version
    ])
    |> validate_inclusion(:dimension, @valid_dimensions)
    |> validate_number(:composite_score,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
    |> validate_number(:challenge_composite,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
    |> validate_number(:unprompted_score,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
    |> unique_constraint([:transcript_id, :dimension])
  end

  @doc "Returns the list of valid dimension strings."
  def valid_dimensions, do: @valid_dimensions

  @doc "Computes composite score from challenge and unprompted scores."
  @spec compute_composite(float(), float()) :: float()
  def compute_composite(challenge_score, unprompted_score) do
    Float.round(challenge_score * 0.7 + unprompted_score * 0.3, 4)
  end
end
