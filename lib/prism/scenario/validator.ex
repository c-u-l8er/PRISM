defmodule Prism.Scenario.Validator do
  @moduledoc """
  Validates CL challenge coverage across a scenario suite.

  Checks that all 9 dimensions and all active domains have adequate
  coverage. Reports gaps for Phase 4 (Reflect) to address.
  """

  alias Prism.{Domain, Scenario}
  alias Prism.Benchmark.CLCategories

  @min_coverage_ratio 0.10
  @min_scenarios_per_domain 3

  @type coverage_report :: %{
          dimension_coverage: map(),
          domain_coverage: map(),
          gaps: [map()],
          overall_adequate: boolean()
        }

  @doc """
  Validate coverage of a list of scenarios.
  Returns a coverage report with gaps identified.
  """
  @spec validate_coverage([Scenario.t()]) :: coverage_report()
  def validate_coverage(scenarios) do
    dim_coverage = dimension_coverage(scenarios)
    dom_coverage = domain_coverage(scenarios)
    gaps = find_gaps(dim_coverage, dom_coverage)

    %{
      dimension_coverage: dim_coverage,
      domain_coverage: dom_coverage,
      gaps: gaps,
      overall_adequate: gaps == []
    }
  end

  @doc """
  Compute per-dimension scenario counts and mean difficulty.
  """
  @spec dimension_coverage([Scenario.t()]) :: map()
  def dimension_coverage(scenarios) do
    all_dims = CLCategories.dimension_keys()
    total = length(scenarios)

    Enum.map(all_dims, fn dim ->
      dim_str = to_string(dim)

      matching =
        Enum.filter(scenarios, fn s ->
          dim_str in Enum.map(Scenario.dimensions(s), &to_string/1)
        end)

      count = length(matching)

      difficulties =
        matching
        |> Enum.map(& &1.difficulty)
        |> Enum.filter(&is_integer/1)

      mean_difficulty =
        if difficulties == [],
          do: 0.0,
          else: Enum.sum(difficulties) / length(difficulties)

      {dim,
       %{
         count: count,
         ratio: if(total > 0, do: count / total, else: 0.0),
         mean_difficulty: Float.round(mean_difficulty, 2)
       }}
    end)
    |> Map.new()
  end

  @doc """
  Compute per-domain scenario counts.
  """
  @spec domain_coverage([Scenario.t()]) :: map()
  def domain_coverage(scenarios) do
    Domain.all()
    |> Enum.map(fn domain ->
      dom_str = to_string(domain)
      count = Enum.count(scenarios, fn s -> s.domain == dom_str end)

      {domain, %{count: count}}
    end)
    |> Map.new()
  end

  @doc """
  Find coverage gaps.
  """
  @spec find_gaps(map(), map()) :: [map()]
  def find_gaps(dim_coverage, dom_coverage) do
    dim_gaps =
      dim_coverage
      |> Enum.filter(fn {_dim, %{ratio: ratio}} -> ratio < @min_coverage_ratio end)
      |> Enum.map(fn {dim, stats} ->
        %{
          type: :dimension_gap,
          dimension: dim,
          current_ratio: stats.ratio,
          required_ratio: @min_coverage_ratio,
          recommendation: "Compose additional scenarios targeting #{dim}"
        }
      end)

    dom_gaps =
      dom_coverage
      |> Enum.filter(fn {_dom, %{count: count}} -> count < @min_scenarios_per_domain end)
      |> Enum.map(fn {dom, stats} ->
        %{
          type: :domain_gap,
          domain: dom,
          current_count: stats.count,
          required_count: @min_scenarios_per_domain,
          recommendation:
            "Compose #{@min_scenarios_per_domain - stats.count} more scenarios in domain #{dom}"
        }
      end)

    dim_gaps ++ dom_gaps
  end
end
