defmodule Prism.MetaJudgmentTest do
  use ExUnit.Case, async: true

  alias Prism.MetaJudgment

  describe "recommendation_from_score/1" do
    test "accept for high scores" do
      assert MetaJudgment.recommendation_from_score(0.9) == "accept"
      assert MetaJudgment.recommendation_from_score(0.7) == "accept"
    end

    test "flag for medium scores" do
      assert MetaJudgment.recommendation_from_score(0.6) == "flag"
      assert MetaJudgment.recommendation_from_score(0.5) == "flag"
    end

    test "reject for low scores" do
      assert MetaJudgment.recommendation_from_score(0.3) == "reject"
      assert MetaJudgment.recommendation_from_score(0.0) == "reject"
    end
  end

  describe "quality_weight/1" do
    test "accept gets full weight" do
      assert MetaJudgment.quality_weight("accept") == 1.0
    end

    test "flag gets reduced weight" do
      assert MetaJudgment.quality_weight("flag") == 0.7
    end

    test "reject gets zero weight" do
      assert MetaJudgment.quality_weight("reject") == 0.0
    end
  end

  describe "same_model_family?/2" do
    test "same family detected" do
      assert MetaJudgment.same_model_family?("claude-sonnet-4-20250514", "claude-3-opus") == true
      assert MetaJudgment.same_model_family?("gpt-4o", "gpt-4-turbo") == true
    end

    test "different families detected" do
      assert MetaJudgment.same_model_family?("claude-sonnet-4-20250514", "gpt-4o") == false
      assert MetaJudgment.same_model_family?("gemini-pro", "gpt-4o") == false
    end
  end
end
