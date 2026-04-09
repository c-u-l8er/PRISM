defmodule Prism.Sequence do
  @moduledoc """
  Ecto schema for scenario sequences (closed-loop testing).

  A sequence is an ordered list of scenarios run against the SAME memory state
  (no reset between scenarios). This tests whether the memory system actually
  gets better from its own usage.

  S1 establishes baseline + generates outcome feedback.
  S2 probes whether retrieval improved from S1's feedback.
  S3 introduces contradictions and checks compounding corrections.

  The key metric is **loop closure rate** — the slope of per-pass retrieval
  scores. Positive slope = system is learning. Zero = pipeline behavior.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @valid_domains Prism.Domain.all_strings()

  schema "prism_sequences" do
    field(:name, :string)
    field(:description, :string)
    field(:scenario_ids, {:array, :binary_id})
    field(:domain, :string)
    field(:pass_count, :integer, default: 3)

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end

  @doc "Changeset for creating a new sequence."
  def changeset(sequence, attrs) do
    sequence
    |> cast(attrs, [:name, :description, :scenario_ids, :domain, :pass_count])
    |> validate_required([:name, :scenario_ids, :domain])
    |> validate_inclusion(:domain, @valid_domains)
    |> validate_length(:scenario_ids, min: 2, message: "sequences need at least 2 scenarios")
    |> validate_number(:pass_count, greater_than_or_equal_to: 2, less_than_or_equal_to: 10)
  end
end
