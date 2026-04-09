defmodule Prism.Run do
  @moduledoc """
  Ecto schema for execution runs.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ~w(pending interacting judging meta_judging completed failed cancelled)

  schema "prism_runs" do
    field(:llm_backend, :string)
    field(:judge_models, :map, default: %{})
    field(:meta_judge_model, :string)
    field(:cycle_number, :integer)
    field(:started_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)
    field(:status, :string, default: "pending")
    field(:aggregate_scores, :map)
    field(:weighted_total, :float)
    field(:loop_closure_rate, :float)
    field(:confidence_intervals, :map)
    field(:cost_usd, :float)
    field(:error_message, :string)
    field(:metadata, :map)

    belongs_to(:suite, Prism.Suite)
    belongs_to(:system, Prism.System, foreign_key: :system_id)

    has_many(:transcripts, Prism.Transcript, foreign_key: :run_id)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :suite_id,
      :system_id,
      :llm_backend,
      :judge_models,
      :meta_judge_model,
      :cycle_number,
      :status,
      :aggregate_scores,
      :weighted_total,
      :loop_closure_rate,
      :confidence_intervals,
      :cost_usd,
      :error_message,
      :metadata
    ])
    |> validate_required([:suite_id, :system_id, :llm_backend, :cycle_number])
    |> validate_inclusion(:status, @valid_statuses)
  end

  def status_changeset(run, status) do
    changes =
      case status do
        "pending" -> %{status: status}
        s when s in ~w(interacting judging meta_judging) -> %{status: status}
        "completed" -> %{status: status, completed_at: DateTime.utc_now()}
        "failed" -> %{status: status, completed_at: DateTime.utc_now()}
        "cancelled" -> %{status: status, completed_at: DateTime.utc_now()}
      end

    change(run, changes)
  end
end
