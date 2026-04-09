defmodule Prism.Scenario.ValidatorTest do
  use ExUnit.Case, async: true

  alias Prism.Scenario.Validator

  # Build a minimal scenario struct for testing.
  # cl_challenges must be a map with a "dimensions" key (list of dimension strings).
  defp make_scenario(attrs) do
    dims = attrs[:dimensions] || ["stability"]

    %Prism.Scenario{
      id: Ecto.UUID.generate(),
      kind: "anchor",
      domain: attrs[:domain] || "code",
      difficulty: attrs[:difficulty] || 3,
      persona: %{},
      sessions: [],
      cl_challenges: %{"dimensions" => dims, "challenges" => []}
    }
  end

  describe "validate_coverage/1" do
    test "returns adequate for well-covered suite" do
      # Create scenarios covering all dimensions and domains
      dims = Prism.Benchmark.CLCategories.dimension_strings()
      domains = Prism.Domain.all_strings()

      scenarios =
        for dim <- dims, dom <- domains do
          make_scenario(domain: dom, dimensions: [dim])
        end

      coverage = Validator.validate_coverage(scenarios)
      assert coverage.overall_adequate
      assert coverage.gaps == []
    end

    test "detects dimension gaps for empty suite" do
      coverage = Validator.validate_coverage([])
      refute coverage.overall_adequate
      assert length(coverage.gaps) > 0
    end

    test "detects domain gaps" do
      # Only code domain scenarios
      scenarios =
        for _ <- 1..10 do
          make_scenario(domain: "code")
        end

      coverage = Validator.validate_coverage(scenarios)
      domain_gaps = Enum.filter(coverage.gaps, &(&1.type == :domain_gap))
      # Should have gaps for non-code domains
      assert length(domain_gaps) > 0
    end
  end

  describe "dimension_coverage/1" do
    test "computes per-dimension stats" do
      scenarios = [
        make_scenario(difficulty: 2, dimensions: ["stability"]),
        make_scenario(difficulty: 4, dimensions: ["stability"])
      ]

      coverage = Validator.dimension_coverage(scenarios)
      assert coverage[:stability].count == 2
      assert_in_delta coverage[:stability].mean_difficulty, 3.0, 0.01
    end
  end
end
