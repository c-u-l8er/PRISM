defmodule Prism.MetaJudgment do
  @moduledoc """
  Ecto schema for Layer 3 meta-judgments.

  Meta-judges evaluate Layer 2 judgments on three axes:
  consistency, evidence grounding, and rubric compliance.

  Critical rule: the meta-judge MUST use a different model family
  than the L2 judge it evaluates. This is enforced at application level.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_recommendations ~w(accept flag reject)

  schema "prism_meta_judgments" do
    field(:meta_judge_model, :string)
    field(:consistency_score, :float)
    field(:evidence_grounding_score, :float)
    field(:rubric_compliance_score, :float)
    field(:composite_score, :float)
    field(:recommendation, :string)
    field(:reasoning, :string)
    field(:raw_response, :map)

    belongs_to(:judgment, Prism.Judgment)

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end

  @doc "Changeset for creating a new meta-judgment."
  def changeset(meta, attrs) do
    meta
    |> cast(attrs, [
      :judgment_id,
      :meta_judge_model,
      :consistency_score,
      :evidence_grounding_score,
      :rubric_compliance_score,
      :composite_score,
      :recommendation,
      :reasoning,
      :raw_response
    ])
    |> validate_required([
      :judgment_id,
      :meta_judge_model,
      :consistency_score,
      :evidence_grounding_score,
      :rubric_compliance_score,
      :composite_score,
      :recommendation
    ])
    |> validate_inclusion(:recommendation, @valid_recommendations)
    |> validate_score_range(:consistency_score)
    |> validate_score_range(:evidence_grounding_score)
    |> validate_score_range(:rubric_compliance_score)
    |> validate_score_range(:composite_score)
    |> unique_constraint([:judgment_id])
  end

  defp validate_score_range(changeset, field) do
    validate_number(changeset, field,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
  end

  @doc """
  Computes the composite score from three axes (equal weight).
  """
  @spec compute_composite(float(), float(), float()) :: float()
  def compute_composite(consistency, grounding, compliance) do
    Float.round((consistency + grounding + compliance) / 3.0, 4)
  end

  @doc """
  Determines recommendation from composite score.

  - ≥ 0.7 → :accept
  - 0.5-0.7 → :flag (widen CIs)
  - < 0.5 → :reject (re-run with different model)
  """
  @spec recommendation_from_score(float()) :: String.t()
  def recommendation_from_score(score) when score >= 0.7, do: "accept"
  def recommendation_from_score(score) when score >= 0.5, do: "flag"
  def recommendation_from_score(_score), do: "reject"

  @doc """
  Returns the quality weight for score aggregation.

  - Accepted: 1.0
  - Flagged: 0.7
  - Rejected: excluded (returns 0.0)
  """
  @spec quality_weight(String.t()) :: float()
  def quality_weight("accept"), do: 1.0
  def quality_weight("flag"), do: 0.7
  def quality_weight("reject"), do: 0.0

  @doc """
  Checks if two models are from the same family.
  Used to enforce the cross-model requirement.
  """
  @spec same_model_family?(String.t(), String.t()) :: boolean()
  def same_model_family?(model_a, model_b) do
    family(model_a) == family(model_b)
  end

  defp family(model) do
    cond do
      String.contains?(model, "claude") or String.contains?(model, "anthropic") -> :anthropic
      String.contains?(model, "gpt") or String.contains?(model, "openai") -> :openai
      String.contains?(model, "gemini") or String.contains?(model, "google") -> :google
      String.contains?(model, "llama") or String.contains?(model, "meta") -> :meta
      String.contains?(model, "mistral") -> :mistral
      true -> :unknown
    end
  end
end
