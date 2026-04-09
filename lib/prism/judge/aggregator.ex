defmodule Prism.Judge.Aggregator do
  @moduledoc """
  Score aggregation across Layer 2 judgments, weighted by Layer 3 quality.

  Computes per-dimension scores, composite PRISM scores, domain-filtered
  scores, and confidence intervals via bootstrap resampling.
  """

  alias Prism.MetaJudgment
  alias Prism.Benchmark.CLCategories

  @bootstrap_iterations 1000
  @confidence_level 0.95

  @doc """
  Aggregate scores from judgments + meta-judgments for a run.

  Returns per-dimension scores, composite, and confidence intervals.
  """
  @spec aggregate([map()], [map()], keyword()) :: map()
  def aggregate(judgments, meta_judgments, opts \\ []) do
    weights = Keyword.get(opts, :weights, CLCategories.weights())
    domain_filter = Keyword.get(opts, :domain)

    # Build meta-judgment lookup
    meta_map =
      Map.new(meta_judgments, fn m ->
        {m.judgment_id || Map.get(m, :judgment_id), m}
      end)

    # Filter and weight judgments
    weighted =
      judgments
      |> maybe_filter_domain(domain_filter)
      |> Enum.map(fn j ->
        meta = Map.get(meta_map, j.id || Map.get(j, :id))
        quality = quality_weight(meta)
        {j, quality}
      end)
      |> Enum.filter(fn {_j, quality} -> quality > 0.0 end)

    # Per-dimension scores
    dim_scores = compute_dimension_scores(weighted)

    # Composite score
    composite = compute_composite(dim_scores, weights)

    # Confidence intervals
    cis = bootstrap_confidence_intervals(weighted, weights)

    # Meta-judge quality stats
    meta_stats = compute_meta_stats(meta_judgments)

    %{
      dimension_scores: dim_scores,
      weighted_total: composite,
      confidence_intervals: cis,
      meta_judge_stats: meta_stats
    }
  end

  @doc """
  Aggregate with domain filtering for domain-specific leaderboard entries.
  """
  @spec aggregate_by_domain([map()], [map()], String.t(), keyword()) :: map()
  def aggregate_by_domain(judgments, meta_judgments, domain, opts \\ []) do
    aggregate(judgments, meta_judgments, Keyword.put(opts, :domain, domain))
  end

  # --- Internal ---

  defp compute_dimension_scores(weighted_judgments) do
    weighted_judgments
    |> Enum.group_by(fn {j, _w} -> j.dimension || Map.get(j, :dimension) end)
    |> Enum.map(fn {dim, entries} ->
      total_weight = Enum.reduce(entries, 0.0, fn {_j, w}, acc -> acc + w end)

      if total_weight > 0 do
        weighted_sum =
          Enum.reduce(entries, 0.0, fn {j, w}, acc ->
            score = j.composite_score || Map.get(j, :composite_score, 0.0)
            acc + score * w
          end)

        {dim, Float.round(weighted_sum / total_weight, 4)}
      else
        {dim, 0.0}
      end
    end)
    |> Map.new()
  end

  defp compute_composite(dim_scores, weights) do
    Enum.reduce(weights, 0.0, fn {dim, weight}, acc ->
      dim_str = to_string(dim)
      score = Map.get(dim_scores, dim_str, 0.0)
      acc + score * weight
    end)
    |> Float.round(4)
  end

  defp bootstrap_confidence_intervals(weighted_judgments, weights) do
    if length(weighted_judgments) < 3 do
      # Not enough data for bootstrap
      %{lower: 0.0, upper: 1.0, method: "insufficient_data"}
    else
      composites =
        1..@bootstrap_iterations
        |> Enum.map(fn _ ->
          sample =
            Enum.map(1..length(weighted_judgments), fn _ ->
              Enum.random(weighted_judgments)
            end)

          dim_scores = compute_dimension_scores(sample)
          compute_composite(dim_scores, weights)
        end)
        |> Enum.sort()

      lower_idx = round(@bootstrap_iterations * (1 - @confidence_level) / 2)
      upper_idx = round(@bootstrap_iterations * (1 + @confidence_level) / 2) - 1

      %{
        lower: Enum.at(composites, max(lower_idx, 0)),
        upper: Enum.at(composites, min(upper_idx, @bootstrap_iterations - 1)),
        method: "bootstrap_#{@bootstrap_iterations}"
      }
    end
  end

  # No meta-judgment = full weight (PRISM-lite)
  defp quality_weight(nil), do: 1.0

  defp quality_weight(meta) do
    rec = meta.recommendation || Map.get(meta, :recommendation)
    MetaJudgment.quality_weight(rec)
  end

  defp compute_meta_stats(meta_judgments) do
    total = length(meta_judgments)

    if total == 0 do
      %{accept_rate: nil, flag_rate: nil, reject_rate: nil}
    else
      counts =
        Enum.frequencies_by(meta_judgments, fn m ->
          m.recommendation || Map.get(m, :recommendation)
        end)

      %{
        accept_rate: Float.round(Map.get(counts, "accept", 0) / total, 3),
        flag_rate: Float.round(Map.get(counts, "flag", 0) / total, 3),
        reject_rate: Float.round(Map.get(counts, "reject", 0) / total, 3)
      }
    end
  end

  defp maybe_filter_domain(judgments, nil), do: judgments

  defp maybe_filter_domain(judgments, domain) do
    # Domain filtering requires joining through transcript → scenario
    # For now, pass through — actual filtering happens at query level
    Enum.filter(judgments, fn j ->
      scenario_domain = get_in(j, [:scenario, :domain]) || Map.get(j, :domain)
      is_nil(scenario_domain) || to_string(scenario_domain) == to_string(domain)
    end)
  end
end
