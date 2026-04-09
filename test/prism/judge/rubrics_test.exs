defmodule Prism.Judge.RubricsTest do
  use ExUnit.Case, async: true

  alias Prism.Judge.Rubrics

  describe "get/1" do
    test "returns rubric for each valid dimension" do
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

      for dim <- dimensions do
        rubric = Rubrics.get(dim)
        assert rubric.dimension == dim
        assert rubric.version == "v2.0"
        assert Map.has_key?(rubric, :challenge_criteria)
        assert Map.has_key?(rubric, :unprompted_indicators)
        assert Map.has_key?(rubric, :domain_notes)
      end
    end

    test "returns error for unknown dimension" do
      assert %{error: "Unknown dimension"} = Rubrics.get("unknown")
    end
  end

  describe "all/0" do
    test "returns rubrics for all 9 dimensions" do
      all = Rubrics.all()
      assert map_size(all) == 9
    end
  end

  describe "version/0" do
    test "returns version string" do
      assert Rubrics.version() == "v2.0"
    end
  end
end
