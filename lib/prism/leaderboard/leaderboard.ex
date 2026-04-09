defmodule Prism.Leaderboard do
  @moduledoc """
  Computes and queries the PRISM leaderboard.

  The leaderboard tracks 9-dimensional CL scores per system × model × cycle × domain.
  Supports domain filtering, loop closure rate display, meta-judge quality
  indicators, trend analysis over cycles, and head-to-head comparisons.
  """

  # These will be used when DB queries are implemented:
  # alias Prism.Benchmark.CLCategories
  # alias Prism.Judge.Aggregator

  @doc """
  Compute a leaderboard entry from aggregated judgment results.

  Includes per-dimension scores, composite, loop closure rate,
  meta-judge quality stats, and confidence intervals.
  """
  @spec compute_entry(map(), keyword()) :: map()
  def compute_entry(aggregation, opts \\ []) do
    run_id = Keyword.get(opts, :run_id)
    cycle = Keyword.get(opts, :cycle)
    system_name = Keyword.get(opts, :system_name)
    llm_backend = Keyword.get(opts, :llm_backend)
    domain = Keyword.get(opts, :domain)
    loop_closure_rate = Keyword.get(opts, :loop_closure_rate)

    %{
      cycle_number: cycle,
      system_name: system_name,
      llm_backend: llm_backend,
      domain: domain,
      # 9 CL dimension scores
      stability_score: Map.get(aggregation.dimension_scores, "stability"),
      plasticity_score: Map.get(aggregation.dimension_scores, "plasticity"),
      knowledge_update_score: Map.get(aggregation.dimension_scores, "knowledge_update"),
      temporal_score: Map.get(aggregation.dimension_scores, "temporal"),
      consolidation_score: Map.get(aggregation.dimension_scores, "consolidation"),
      uncertainty_score: Map.get(aggregation.dimension_scores, "epistemic_awareness"),
      transfer_score: Map.get(aggregation.dimension_scores, "transfer"),
      forgetting_score: Map.get(aggregation.dimension_scores, "forgetting"),
      feedback_score: Map.get(aggregation.dimension_scores, "feedback"),
      # Composite
      weighted_total: aggregation.weighted_total,
      loop_closure_rate: loop_closure_rate,
      # Meta-judge quality
      meta_judge_accept_rate: get_in(aggregation, [:meta_judge_stats, :accept_rate]),
      meta_judge_flag_rate: get_in(aggregation, [:meta_judge_stats, :flag_rate]),
      meta_judge_reject_rate: get_in(aggregation, [:meta_judge_stats, :reject_rate]),
      # Confidence
      confidence_intervals: aggregation.confidence_intervals,
      # Provenance
      run_id: run_id
    }
  end

  @doc """
  Get the leaderboard for a cycle, optionally filtered by domain and dimension.

  Options:
  - `:cycle` — cycle number (default: latest)
  - `:domain` — filter by domain (nil = aggregate across all domains)
  - `:dimension` — sort by this dimension instead of weighted_total
  - `:limit` — max entries (default: 50)
  """
  @spec get(keyword()) :: [map()]
  def get(opts \\ []) do
    _cycle = Keyword.get(opts, :cycle)
    _domain = Keyword.get(opts, :domain)
    _dimension = Keyword.get(opts, :dimension)
    _limit = Keyword.get(opts, :limit, 50)

    # TODO: Query from prism_leaderboard table
    # Placeholder: return empty list until DB is populated
    []
  end

  @doc """
  Get leaderboard history for a system over cycles.
  Used for trend analysis.
  """
  @spec history(String.t(), keyword()) :: [map()]
  def history(_system_name, opts \\ []) do
    _from_cycle = Keyword.get(opts, :from_cycle, 1)
    _to_cycle = Keyword.get(opts, :to_cycle)
    _domain = Keyword.get(opts, :domain)

    # TODO: Query from prism_leaderboard table
    []
  end

  @doc """
  Head-to-head comparison of two systems across all 9 dimensions.
  """
  @spec compare(String.t(), String.t(), keyword()) :: map()
  def compare(system_a, system_b, opts \\ []) do
    cycle = Keyword.get(opts, :cycle)
    domain = Keyword.get(opts, :domain)

    # TODO: Query both systems and compute deltas
    %{
      system_a: system_a,
      system_b: system_b,
      cycle: cycle,
      domain: domain,
      dimensions: %{},
      winner: nil,
      statistically_significant: false
    }
  end

  @doc """
  Get the top system per CL dimension.
  """
  @spec dimension_leaders(keyword()) :: map()
  def dimension_leaders(opts \\ []) do
    _cycle = Keyword.get(opts, :cycle)
    _domain = Keyword.get(opts, :domain)

    dimensions = [
      "stability",
      "plasticity",
      "knowledge_update",
      "temporal",
      "consolidation",
      "epistemic_awareness",
      "transfer",
      "forgetting",
      "feedback"
    ]

    # TODO: Query top system per dimension
    Enum.map(dimensions, fn dim -> {dim, nil} end) |> Map.new()
  end

  @doc """
  Check if two systems' scores are within overlapping confidence intervals.
  Systems within overlapping CIs should be reported as tied.
  """
  @spec statistically_tied?(map(), map()) :: boolean()
  def statistically_tied?(entry_a, entry_b) do
    ci_a = entry_a[:confidence_intervals] || %{}
    ci_b = entry_b[:confidence_intervals] || %{}

    lower_a = Map.get(ci_a, :lower, 0.0)
    upper_a = Map.get(ci_a, :upper, 1.0)
    lower_b = Map.get(ci_b, :lower, 0.0)
    upper_b = Map.get(ci_b, :upper, 1.0)

    # Overlapping if one's lower is within the other's range
    lower_a <= upper_b && lower_b <= upper_a
  end

  @doc """
  Format a leaderboard entry for display.
  """
  @spec format_entry(map()) :: String.t()
  def format_entry(entry) do
    loop_str =
      case entry[:loop_closure_rate] do
        nil -> "N/A"
        rate when rate > 0.05 -> "#{Float.round(rate, 2)} ↑"
        rate when rate < -0.05 -> "#{Float.round(rate, 2)} ↓"
        rate -> "#{Float.round(rate, 2)} →"
      end

    "#{entry.system_name}\t#{Float.round(entry.weighted_total || 0.0, 3)}\t#{loop_str}"
  end
end
