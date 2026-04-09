defmodule Prism.Suite do
  @moduledoc """
  Ecto schema for evaluation suites (one per cycle).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @valid_statuses ~w(draft validated active retired)

  schema "prism_suites" do
    field(:cycle_number, :integer)
    field(:simulator_model, :string)
    field(:cl_category_weights, :map)
    field(:total_scenarios, :integer)
    field(:anchor_count, :integer, default: 0)
    field(:frontier_count, :integer, default: 0)
    field(:validated_scenarios, :integer)
    field(:coverage_scores, :map)
    field(:status, :string, default: "draft")
    field(:metadata, :map)

    has_many(:scenarios, Prism.Scenario, foreign_key: :suite_id)

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end

  def changeset(suite, attrs) do
    suite
    |> cast(attrs, [
      :cycle_number,
      :simulator_model,
      :cl_category_weights,
      :total_scenarios,
      :anchor_count,
      :frontier_count,
      :validated_scenarios,
      :coverage_scores,
      :status,
      :metadata
    ])
    |> validate_required([
      :cycle_number,
      :simulator_model,
      :cl_category_weights,
      :total_scenarios
    ])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:cycle_number, greater_than: 0)
  end
end
