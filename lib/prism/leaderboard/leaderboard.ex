defmodule Prism.Leaderboard do
  @moduledoc """
  Computes and queries the PRISM leaderboard.

  The leaderboard tracks 9-dimensional CL scores per system × model × cycle.
  Supports filtering by dimension, trend analysis over cycles, and
  head-to-head comparisons.
  """

  alias Prism.Benchmark.CLCategories

  @doc "Compute leaderboard entry from a completed run's judged results"
  def compute_entry(run_id, cl_scores, weights) do
    weighted_total = compute_weighted_total(cl_scores, weights)

    # Bootstrap 95% confidence intervals
    cis = compute_confidence_intervals(run_id)

    %{
      run_id: run_id,
      stability_score: Map.get(cl_scores, :stability),
      plasticity_score: Map.get(cl_scores, :plasticity),
      knowledge_update_score: Map.get(cl_scores, :knowledge_update),
      consolidation_score: Map.get(cl_scores, :consolidation),
      temporal_score: Map.get(cl_scores, :temporal),
      transfer_score: Map.get(cl_scores, :transfer),
      uncertainty_score: Map.get(cl_scores, :uncertainty),
      forgetting_score: Map.get(cl_scores, :forgetting),
      feedback_score: Map.get(cl_scores, :feedback),
      weighted_total: weighted_total,
      confidence_intervals: cis
    }
  end

  @doc "Get the current leaderboard, optionally filtered"
  def get(opts \\ %{}) do
    # TODO: Ecto query against prism_leaderboard table
    {:ok, []}
  end

  @doc "Head-to-head comparison of two systems"
  def compare(system_a, system_b, opts \\ %{}) do
    # TODO: Query both systems' latest scores, compute deltas
    {:ok, %{system_a: system_a, system_b: system_b, dimensions: %{}}}
  end

  @doc "Get the leader for each CL dimension"
  def dimension_leaders(opts \\ %{}) do
    CLCategories.ids()
    |> Enum.map(fn dim ->
      # TODO: Query for top system per dimension
      {dim, %{system: nil, score: nil}}
    end)
    |> Map.new()
  end

  @doc "Get leaderboard history for trend analysis"
  def history(system, opts \\ %{}) do
    # TODO: Query prism_leaderboard over multiple cycles
    {:ok, []}
  end

  defp compute_weighted_total(cl_scores, weights) do
    Enum.reduce(CLCategories.ids(), 0.0, fn dim, acc ->
      score = Map.get(cl_scores, dim, 0.0) || 0.0
      weight = Map.get(weights, dim, 0.0)
      acc + score * weight
    end)
  end

  defp compute_confidence_intervals(_run_id) do
    # TODO: Bootstrap resampling
    # 1. Load all per-question scores for this run
    # 2. Resample with replacement 1000 times
    # 3. Compute 2.5th and 97.5th percentile per dimension
    %{}
  end
end
