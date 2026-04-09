defmodule Prism.Sequence.ScorerTest do
  use ExUnit.Case, async: true

  alias Prism.Sequence.Scorer

  describe "loop_closure_rate/1" do
    test "positive slope for improving scores" do
      pass_scores = [
        %{"stability" => 0.3, "plasticity" => 0.2},
        %{"stability" => 0.5, "plasticity" => 0.4},
        %{"stability" => 0.7, "plasticity" => 0.6}
      ]

      rate = Scorer.loop_closure_rate(pass_scores)
      assert rate > 0
    end

    test "negative slope for declining scores" do
      pass_scores = [
        %{"stability" => 0.8, "plasticity" => 0.7},
        %{"stability" => 0.5, "plasticity" => 0.4},
        %{"stability" => 0.3, "plasticity" => 0.2}
      ]

      rate = Scorer.loop_closure_rate(pass_scores)
      assert rate < 0
    end

    test "returns 0.0 for empty input" do
      assert Scorer.loop_closure_rate([]) == 0.0
    end

    test "returns 0.0 for single pass" do
      assert Scorer.loop_closure_rate([%{"stability" => 0.5}]) == 0.0
    end
  end

  describe "feedback_latency/1" do
    test "detects improvement on second pass" do
      pass_scores = [
        %{"stability" => 0.3},
        %{"stability" => 0.5},
        %{"stability" => 0.7}
      ]

      latency = Scorer.feedback_latency(pass_scores)
      assert latency == 2
    end

    test "returns nil when no improvement" do
      pass_scores = [
        %{"stability" => 0.5},
        %{"stability" => 0.5},
        %{"stability" => 0.5}
      ]

      assert Scorer.feedback_latency(pass_scores) == nil
    end

    test "returns nil for empty input" do
      assert Scorer.feedback_latency([]) == nil
    end
  end

  describe "plateau_level/1" do
    test "returns the last pass mean" do
      pass_scores = [
        %{"stability" => 0.3},
        %{"stability" => 0.5},
        %{"stability" => 0.7}
      ]

      level = Scorer.plateau_level(pass_scores)
      assert_in_delta level, 0.7, 0.001
    end

    test "returns 0.0 for empty input" do
      assert Scorer.plateau_level([]) == 0.0
    end
  end

  describe "per_dimension_slopes/1" do
    test "returns per-dimension slopes" do
      pass_scores = [
        %{"stability" => 0.3, "plasticity" => 0.8},
        %{"stability" => 0.5, "plasticity" => 0.7},
        %{"stability" => 0.7, "plasticity" => 0.6}
      ]

      slopes = Scorer.per_dimension_slopes(pass_scores)
      assert slopes["stability"] > 0
      assert slopes["plasticity"] < 0
    end

    test "returns empty map for empty input" do
      assert Scorer.per_dimension_slopes([]) == %{}
    end
  end

  describe "linear_slope/1" do
    test "perfect positive slope" do
      assert_in_delta Scorer.linear_slope([1.0, 2.0, 3.0]), 1.0, 0.001
    end

    test "perfect negative slope" do
      assert_in_delta Scorer.linear_slope([3.0, 2.0, 1.0]), -1.0, 0.001
    end

    test "flat line" do
      assert_in_delta Scorer.linear_slope([5.0, 5.0, 5.0]), 0.0, 0.001
    end

    test "returns 0.0 for insufficient data" do
      assert Scorer.linear_slope([]) == 0.0
      assert Scorer.linear_slope([1.0]) == 0.0
    end
  end
end
