defmodule Prism.Sequence.Scorer do
  @moduledoc """
  Computes closed-loop metrics from scenario sequence results.

  Key metrics:
  - **Loop closure rate**: slope of per-pass retrieval scores (positive = learning)
  - **Feedback latency**: interactions before feedback visibly affects retrieval
  - **Correction propagation**: do downstream retrievals reflect belief revisions?
  - **Plateau detection**: does improvement saturate, and at what level?
  """

  @doc """
  Compute all closed-loop metrics from per-pass dimension scores.

  `pass_scores` is a list of maps, one per pass, each mapping dimension → score.
  """
  @spec compute_metrics([map()]) :: map()
  def compute_metrics(pass_scores) when is_list(pass_scores) do
    %{
      loop_closure_rate: loop_closure_rate(pass_scores),
      feedback_latency: feedback_latency(pass_scores),
      plateau_level: plateau_level(pass_scores),
      per_pass_means: per_pass_means(pass_scores),
      per_dimension_slopes: per_dimension_slopes(pass_scores),
      pass_count: length(pass_scores)
    }
  end

  @doc """
  Loop closure rate: linear regression slope of mean scores across passes.

  Positive = system is learning from usage.
  Zero = pipeline behavior (store-retrieve-done).
  Negative = system is degrading from usage.
  """
  @spec loop_closure_rate([map()]) :: float()
  def loop_closure_rate(pass_scores) do
    means = per_pass_means(pass_scores)
    linear_slope(means)
  end

  @doc """
  Feedback latency: which pass first shows measurable improvement.
  Returns pass number (1-indexed) or nil if no improvement detected.
  """
  @spec feedback_latency([map()]) :: non_neg_integer() | nil
  def feedback_latency(pass_scores) do
    means = per_pass_means(pass_scores)

    case means do
      [] ->
        nil

      [_] ->
        nil

      [first | rest] ->
        rest
        |> Enum.with_index(2)
        |> Enum.find(fn {score, _idx} -> score > first + 0.05 end)
        |> case do
          {_score, idx} -> idx
          nil -> nil
        end
    end
  end

  @doc """
  Plateau level: the highest mean score achieved in any pass.
  """
  @spec plateau_level([map()]) :: float()
  def plateau_level(pass_scores) do
    case per_pass_means(pass_scores) do
      [] -> 0.0
      means -> Enum.max(means)
    end
  end

  @doc """
  Compute mean score for each pass across all dimensions.
  """
  @spec per_pass_means([map()]) :: [float()]
  def per_pass_means(pass_scores) do
    Enum.map(pass_scores, fn scores ->
      values = Map.values(scores) |> Enum.filter(&is_number/1)

      case values do
        [] -> 0.0
        vals -> Float.round(Enum.sum(vals) / length(vals), 4)
      end
    end)
  end

  @doc """
  Compute per-dimension slope across passes.
  Shows which dimensions improve vs degrade.
  """
  @spec per_dimension_slopes([map()]) :: map()
  def per_dimension_slopes(pass_scores) do
    # Collect all dimension keys
    all_dims =
      pass_scores
      |> Enum.flat_map(&Map.keys/1)
      |> Enum.uniq()

    Enum.map(all_dims, fn dim ->
      values =
        Enum.map(pass_scores, fn scores ->
          Map.get(scores, dim, 0.0)
        end)

      {dim, Float.round(linear_slope(values), 4)}
    end)
    |> Map.new()
  end

  @doc """
  Simple linear regression slope for a list of values.
  x values are 0, 1, 2, ... (pass indices).
  """
  @spec linear_slope([number()]) :: float()
  def linear_slope([]), do: 0.0
  def linear_slope([_]), do: 0.0

  def linear_slope(values) do
    n = length(values)

    xs = Enum.to_list(0..(n - 1))
    ys = values

    x_mean = Enum.sum(xs) / n
    y_mean = Enum.sum(ys) / n

    numerator =
      Enum.zip(xs, ys)
      |> Enum.map(fn {x, y} -> (x - x_mean) * (y - y_mean) end)
      |> Enum.sum()

    denominator =
      xs
      |> Enum.map(fn x -> (x - x_mean) * (x - x_mean) end)
      |> Enum.sum()

    if denominator == 0, do: 0.0, else: Float.round(numerator / denominator, 4)
  end
end
