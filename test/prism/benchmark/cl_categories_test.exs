defmodule Prism.Benchmark.CLCategoriesTest do
  use ExUnit.Case, async: true

  alias Prism.Benchmark.CLCategories

  describe "all/0" do
    test "returns 9 categories" do
      assert length(CLCategories.all()) == 9
    end

    test "each category has required fields" do
      for cat <- CLCategories.all() do
        assert Map.has_key?(cat, :id)
        assert Map.has_key?(cat, :name)
        assert Map.has_key?(cat, :weight)
        assert Map.has_key?(cat, :description)
        assert Map.has_key?(cat, :question_templates)
        assert Map.has_key?(cat, :difficulty_levels)
        assert Map.has_key?(cat, :external_benchmarks)
      end
    end
  end

  describe "default_weights/0" do
    test "weights sum to 1.0" do
      weights = CLCategories.default_weights()
      sum = weights |> Map.values() |> Enum.sum()
      assert_in_delta sum, 1.0, 0.01
    end

    test "returns a map of atom keys to floats" do
      weights = CLCategories.default_weights()
      assert is_map(weights)
      assert Map.has_key?(weights, :stability)
      assert is_float(weights[:stability])
    end
  end

  describe "validate_weights/1" do
    test "accepts valid weights" do
      assert :ok = CLCategories.validate_weights(CLCategories.default_weights())
    end

    test "rejects weights that don't sum to 1.0" do
      bad_weights = %{stability: 0.5, plasticity: 0.3}
      assert {:error, _} = CLCategories.validate_weights(bad_weights)
    end
  end

  describe "get/1" do
    test "returns category by id" do
      cat = CLCategories.get(:stability)
      assert cat.id == :stability
      assert cat.weight == 0.20
    end

    test "returns nil for unknown id" do
      assert CLCategories.get(:nonexistent) == nil
    end
  end

  describe "ids/0" do
    test "returns 9 atom ids" do
      ids = CLCategories.ids()
      assert length(ids) == 9
      assert :stability in ids
      assert :feedback in ids
    end
  end

  describe "dimension_keys/0 and dimension_strings/0" do
    test "dimension_keys equals ids" do
      assert CLCategories.dimension_keys() == CLCategories.ids()
    end

    test "dimension_strings returns string versions" do
      strings = CLCategories.dimension_strings()
      assert "stability" in strings
      assert "plasticity" in strings
      assert length(strings) == 9
    end
  end

  describe "challenge_patterns/1" do
    test "returns templates for valid dimension" do
      patterns = CLCategories.challenge_patterns(:stability)
      assert length(patterns) == 3
      assert Enum.all?(patterns, &Map.has_key?(&1, :type))
    end

    test "returns empty list for unknown dimension" do
      assert CLCategories.challenge_patterns(:nonexistent) == []
    end
  end

  describe "difficulty_levels/1" do
    test "returns 5 levels for valid dimension" do
      levels = CLCategories.difficulty_levels(:stability)
      assert map_size(levels) == 5
      assert Map.has_key?(levels, 1)
      assert Map.has_key?(levels, 5)
    end

    test "returns empty map for unknown dimension" do
      assert CLCategories.difficulty_levels(:nonexistent) == %{}
    end
  end
end
