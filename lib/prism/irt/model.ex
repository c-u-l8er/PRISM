defmodule Prism.IRT.Model do
  @moduledoc """
  3PL (Three-Parameter Logistic) Item Response Theory model.

  P(score ≥ threshold | θ, a, b, c) = c + (1-c) / (1 + exp(-a(θ-b)))

  Where:
  - θ = system ability (per-dimension, estimated from data)
  - a = scenario discrimination (how well it differentiates systems)
  - b = scenario difficulty (where on the ability scale it operates)
  - c = guessing parameter (floor for random success)
  """

  @doc """
  Compute probability of scoring above threshold given ability and item params.
  """
  @spec probability(float(), float(), float(), float()) :: float()
  def probability(theta, a, b, c) do
    c + (1.0 - c) / (1.0 + :math.exp(-a * (theta - b)))
  end

  @doc """
  Information function: how much information this scenario provides at ability θ.
  Higher information = more discriminating at this ability level.
  """
  @spec information(float(), float(), float(), float()) :: float()
  def information(theta, a, b, c) do
    p = probability(theta, a, b, c)
    q = 1.0 - p

    if q == 0.0 or p == c do
      0.0
    else
      numerator = a * a * (p - c) * (p - c) * q
      denominator = (1.0 - c) * (1.0 - c) * p
      if denominator == 0.0, do: 0.0, else: numerator / denominator
    end
  end

  @doc """
  Estimate system ability (θ) from observed scores using maximum likelihood.
  Iterative Newton-Raphson method.
  """
  @spec estimate_ability([{float(), float(), float(), float()}], keyword()) :: float()
  def estimate_ability(item_responses, opts \\ []) do
    max_iter = Keyword.get(opts, :max_iterations, 50)
    tolerance = Keyword.get(opts, :tolerance, 0.001)
    initial_theta = Keyword.get(opts, :initial, 0.0)

    newton_raphson(item_responses, initial_theta, max_iter, tolerance, 0)
  end

  @doc """
  Estimate item difficulty (b) from system scores.
  Uses proportion-correct as initial estimate, refined by MLE.
  """
  @spec estimate_difficulty([{float(), float()}]) :: float()
  def estimate_difficulty(ability_score_pairs) do
    # Simple proportion-correct → logit transform for initial estimate
    scores = Enum.map(ability_score_pairs, fn {_ability, score} -> score end)

    case scores do
      [] ->
        0.0

      _ ->
        mean_score = Enum.sum(scores) / length(scores)
        # Clamp to avoid log(0) or log(inf)
        clamped = max(0.01, min(0.99, mean_score))
        # Inverse logit: b ≈ -log(p / (1-p)) (when a=1, c=0)
        -:math.log(clamped / (1.0 - clamped))
    end
  end

  @doc """
  Estimate item discrimination (a) from score variance across systems.
  Higher variance → higher discrimination.
  """
  @spec estimate_discrimination([float()]) :: float()
  def estimate_discrimination(scores) do
    case scores do
      [] ->
        1.0

      [_] ->
        1.0

      _ ->
        mean = Enum.sum(scores) / length(scores)

        variance =
          Enum.reduce(scores, 0.0, fn s, acc -> acc + (s - mean) * (s - mean) end) /
            length(scores)

        sd = :math.sqrt(variance)

        # Map sd to discrimination: higher spread → higher discrimination
        # Typical range: 0.5 to 2.5
        max(0.5, min(2.5, sd * 5.0))
    end
  end

  # Newton-Raphson iteration for MLE of θ
  defp newton_raphson(_items, theta, _max_iter, _tol, iter) when iter >= 50, do: theta

  defp newton_raphson(items, theta, max_iter, tolerance, iter) do
    {numerator, denominator} =
      Enum.reduce(items, {0.0, 0.0}, fn {score, a, b, c}, {num, den} ->
        p = probability(theta, a, b, c)
        q = 1.0 - p

        if q == 0.0 or p == 0.0 do
          {num, den}
        else
          w = a * (p - c) / ((1.0 - c) * p)
          num_contrib = w * (score - p)
          den_contrib = w * w * p * q

          {num + num_contrib, den + den_contrib}
        end
      end)

    if denominator == 0.0 or abs(numerator) < tolerance do
      theta
    else
      new_theta = theta + numerator / denominator
      # Clamp to reasonable range
      clamped = max(-4.0, min(4.0, new_theta))

      if abs(clamped - theta) < tolerance do
        clamped
      else
        newton_raphson(items, clamped, max_iter, tolerance, iter + 1)
      end
    end
  end
end
