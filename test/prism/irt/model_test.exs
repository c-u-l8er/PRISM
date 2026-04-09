defmodule Prism.IRT.ModelTest do
  use ExUnit.Case, async: true

  alias Prism.IRT.Model

  describe "probability/4" do
    test "returns 0.5 when ability equals difficulty (no guessing)" do
      assert_in_delta Model.probability(0.0, 1.0, 0.0, 0.0), 0.5, 0.001
    end

    test "returns close to 1.0 for very high ability" do
      prob = Model.probability(5.0, 1.0, 0.0, 0.0)
      assert prob > 0.99
    end

    test "returns guessing parameter for very low ability" do
      prob = Model.probability(-10.0, 1.0, 0.0, 0.25)
      assert_in_delta prob, 0.25, 0.01
    end

    test "higher discrimination steepens the curve" do
      prob_low = Model.probability(1.0, 0.5, 0.0, 0.0)
      prob_high = Model.probability(1.0, 2.0, 0.0, 0.0)
      assert prob_high > prob_low
    end

    test "probability is bounded [c, 1]" do
      for _ <- 1..100 do
        theta = :rand.uniform() * 10 - 5
        a = :rand.uniform() * 2 + 0.1
        b = :rand.uniform() * 6 - 3
        c = :rand.uniform() * 0.3

        prob = Model.probability(theta, a, b, c)
        assert prob >= c - 0.001
        assert prob <= 1.001
      end
    end
  end

  describe "information/4" do
    test "information is maximized near item difficulty" do
      info_at_b = Model.information(0.0, 1.5, 0.0, 0.1)
      info_far = Model.information(3.0, 1.5, 0.0, 0.1)
      assert info_at_b > info_far
    end

    test "information is non-negative" do
      for _ <- 1..100 do
        theta = :rand.uniform() * 10 - 5
        a = :rand.uniform() * 2 + 0.1
        b = :rand.uniform() * 6 - 3
        c = :rand.uniform() * 0.3

        info = Model.information(theta, a, b, c)
        assert info >= 0
      end
    end

    test "higher discrimination gives more information" do
      info_low = Model.information(0.0, 0.5, 0.0, 0.1)
      info_high = Model.information(0.0, 2.0, 0.0, 0.1)
      assert info_high > info_low
    end
  end

  describe "estimate_ability/2" do
    test "estimates ability from observations" do
      # {score, discrimination, difficulty, guessing}
      observations = [
        {1.0, 1.0, 0.0, 0.1},
        {1.0, 1.0, 0.5, 0.1},
        {1.0, 1.0, 1.0, 0.1},
        {1.0, 1.0, -0.5, 0.1}
      ]

      theta = Model.estimate_ability(observations)
      assert theta > 0
    end

    test "low scores give negative ability" do
      observations = [
        {0.0, 1.0, 0.0, 0.1},
        {0.0, 1.0, 0.5, 0.1},
        {0.0, 1.0, 1.0, 0.1},
        {0.2, 1.0, -0.5, 0.1}
      ]

      theta = Model.estimate_ability(observations)
      assert theta < 0
    end

    test "returns 0.0 for empty observations" do
      assert Model.estimate_ability([]) == 0.0
    end
  end

  describe "estimate_difficulty/1" do
    test "high scores give low difficulty" do
      # estimate_difficulty expects [{ability, score}] tuples
      difficulty = Model.estimate_difficulty([{0.0, 1.0}, {0.0, 0.9}, {0.0, 0.95}, {0.0, 1.0}])
      assert difficulty < 0
    end

    test "low scores give high difficulty" do
      difficulty = Model.estimate_difficulty([{0.0, 0.1}, {0.0, 0.05}, {0.0, 0.15}, {0.0, 0.05}])
      assert difficulty > 0
    end

    test "returns 0.0 for empty scores" do
      assert Model.estimate_difficulty([]) == 0.0
    end
  end

  describe "estimate_discrimination/1" do
    test "returns positive value for varied scores" do
      disc = Model.estimate_discrimination([0.0, 0.2, 0.5, 0.8, 1.0])
      assert disc > 0
    end

    test "returns default for empty scores" do
      assert Model.estimate_discrimination([]) == 1.0
    end
  end
end
