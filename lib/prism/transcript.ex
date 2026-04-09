defmodule Prism.Transcript do
  @moduledoc """
  Ecto schema for interaction transcripts.

  Every Phase 2 interaction produces a full transcript capturing tool calls,
  retrieval contexts, reasoning patterns, and timing data — not just final
  answers. This is the observable evidence that Layer 2 judges analyze.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "prism_transcripts" do
    field(:llm_backend, :string)
    field(:sessions, {:array, :map})
    field(:total_tool_calls, :integer, default: 0)
    field(:total_turns, :integer, default: 0)
    field(:duration_ms, :integer)
    field(:cost_usd, :float)

    belongs_to(:scenario, Prism.Scenario)
    belongs_to(:system, Prism.System, foreign_key: :system_id)
    belongs_to(:run, Prism.Run, foreign_key: :run_id)

    has_many(:judgments, Prism.Judgment, foreign_key: :transcript_id)

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end

  @doc "Changeset for creating a new transcript."
  def changeset(transcript, attrs) do
    transcript
    |> cast(attrs, [
      :scenario_id,
      :system_id,
      :run_id,
      :llm_backend,
      :sessions,
      :total_tool_calls,
      :total_turns,
      :duration_ms,
      :cost_usd
    ])
    |> validate_required([:scenario_id, :system_id, :llm_backend, :sessions])
    |> validate_number(:total_tool_calls, greater_than_or_equal_to: 0)
    |> validate_number(:total_turns, greater_than_or_equal_to: 0)
  end

  @doc "Extracts tool calls from all sessions in the transcript."
  def all_tool_calls(%__MODULE__{sessions: sessions}) when is_list(sessions) do
    sessions
    |> Enum.flat_map(fn session ->
      turns = Map.get(session, "turns") || Map.get(session, :turns) || []

      Enum.flat_map(turns, fn turn ->
        sent = Map.get(turn, "tool_calls_sent") || Map.get(turn, :tool_calls_sent) || []

        received =
          Map.get(turn, "tool_calls_received") || Map.get(turn, :tool_calls_received) || []

        sent ++ received
      end)
    end)
  end

  def all_tool_calls(_), do: []
end
