defmodule Prism.Scenario do
  @moduledoc """
  Ecto schema for PRISM scenarios.

  Scenarios replace legacy benchmark questions. Each scenario is a multi-session
  interaction script with embedded CL challenges and verifiable ground truth
  from real git repositories.

  Two kinds:
  - **anchor**: Git-grounded, script mode, never retired, stable IRT params
  - **frontier**: Evolving, may use adaptive mode, can be promoted to anchor
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_kinds ~w(anchor frontier)
  @valid_domains Prism.Domain.all_strings()
  @valid_retirement_reasons ~w(saturated ambiguous too_hard duplicate)

  schema "prism_scenarios" do
    field(:kind, :string)
    field(:domain, :string)
    field(:difficulty, :integer)
    field(:persona, :map)
    field(:sessions, {:array, :map})
    field(:cl_challenges, :map)

    # IRT parameters
    field(:irt_difficulty_b, :float, default: 0.0)
    field(:irt_discrimination_a, :float, default: 1.0)
    field(:irt_guessing_c, :float, default: 0.1)
    field(:irt_calibrated, :boolean, default: false)

    # Lifecycle
    field(:validation_score, :float)
    field(:promoted_at, :utc_datetime_usec)
    field(:retired_at, :utc_datetime_usec)
    field(:retirement_reason, :string)

    belongs_to(:suite, Prism.Suite, foreign_key: :suite_id)
    belongs_to(:repo_anchor, Prism.RepoAnchor, foreign_key: :repo_anchor_id)

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end

  @doc "Changeset for creating a new scenario."
  def changeset(scenario, attrs) do
    scenario
    |> cast(attrs, [
      :kind,
      :domain,
      :difficulty,
      :persona,
      :sessions,
      :cl_challenges,
      :suite_id,
      :repo_anchor_id,
      :irt_difficulty_b,
      :irt_discrimination_a,
      :irt_guessing_c,
      :validation_score
    ])
    |> validate_required([:kind, :domain, :difficulty, :persona, :sessions, :cl_challenges])
    |> validate_inclusion(:kind, @valid_kinds)
    |> validate_inclusion(:domain, @valid_domains)
    |> validate_number(:difficulty, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_anchor_has_repo()
  end

  @doc "Changeset for retiring a scenario."
  def retire_changeset(scenario, reason) do
    scenario
    |> change(%{retired_at: DateTime.utc_now(), retirement_reason: reason})
    |> validate_inclusion(:retirement_reason, @valid_retirement_reasons)
  end

  @doc "Changeset for promoting a frontier to anchor."
  def promote_changeset(scenario) do
    scenario
    |> change(%{kind: "anchor", promoted_at: DateTime.utc_now()})
  end

  @doc "Changeset for updating IRT parameters."
  def irt_changeset(scenario, attrs) do
    scenario
    |> cast(attrs, [:irt_difficulty_b, :irt_discrimination_a, :irt_guessing_c, :irt_calibrated])
  end

  # Anchors must reference a repo anchor
  defp validate_anchor_has_repo(changeset) do
    kind = get_field(changeset, :kind)
    repo_id = get_field(changeset, :repo_anchor_id)

    if kind == "anchor" && is_nil(repo_id) do
      add_error(changeset, :repo_anchor_id, "anchor scenarios must reference a repo anchor")
    else
      changeset
    end
  end

  @doc "Returns the CL dimensions tested by this scenario."
  def dimensions(%__MODULE__{cl_challenges: challenges}) when is_map(challenges) do
    case Map.get(challenges, "dimensions") || Map.get(challenges, :dimensions) do
      dims when is_list(dims) -> dims
      _ -> []
    end
  end

  def dimensions(_), do: []

  @doc "Returns true if the scenario is active (not retired)."
  def active?(%__MODULE__{retired_at: nil}), do: true
  def active?(_), do: false

  @doc "Returns true if the scenario's IRT parameters have been calibrated."
  def calibrated?(%__MODULE__{irt_calibrated: true}), do: true
  def calibrated?(_), do: false
end
