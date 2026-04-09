defmodule Prism.RepoAnchor do
  @moduledoc """
  Ecto schema for git repo anchors.

  Repo anchors are the ground truth sources for PRISM anchor scenarios.
  Each anchor references a real git repository with a specific commit range,
  key CL-relevant events (refactors, contradictions, pattern transfers),
  and cached file snapshots at key commits.

  The code IS the ground truth — checkout any commit to verify.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "prism_repo_anchors" do
    field(:repo_url, :string)
    field(:license, :string)
    field(:commit_range_from, :string)
    field(:commit_range_to, :string)
    field(:total_commits, :integer)
    field(:clone_path, :string)
    field(:key_events, {:array, :map}, default: [])
    field(:snapshots, :map, default: %{})

    has_many(:scenarios, Prism.Scenario, foreign_key: :repo_anchor_id)

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end

  @doc "Changeset for creating a new repo anchor."
  def changeset(anchor, attrs) do
    anchor
    |> cast(attrs, [
      :repo_url,
      :license,
      :commit_range_from,
      :commit_range_to,
      :total_commits,
      :clone_path,
      :key_events,
      :snapshots
    ])
    |> validate_required([
      :repo_url,
      :license,
      :commit_range_from,
      :commit_range_to,
      :total_commits
    ])
    |> validate_inclusion(
      :license,
      ~w(MIT Apache-2.0 BSD-2-Clause BSD-3-Clause ISC MPL-2.0 Unlicense)
    )
    |> validate_number(:total_commits, greater_than: 0)
  end

  @doc "Returns commits in the key_events that match a specific CL dimension."
  def events_for_dimension(%__MODULE__{key_events: events}, dimension) when is_list(events) do
    dim_str = to_string(dimension)

    Enum.filter(events, fn event ->
      dims = Map.get(event, "cl_dimensions") || Map.get(event, :cl_dimensions) || []
      dim_str in Enum.map(dims, &to_string/1)
    end)
  end

  def events_for_dimension(_, _), do: []

  @doc "Returns the snapshot for a specific commit."
  def snapshot_at(%__MODULE__{snapshots: snapshots}, commit) when is_map(snapshots) do
    Map.get(snapshots, commit)
  end

  def snapshot_at(_, _), do: nil
end
