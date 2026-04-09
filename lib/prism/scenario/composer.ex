defmodule Prism.Scenario.Composer do
  @moduledoc """
  Composes scenario prompts from repo anchors.

  PRISM is a pure data layer — no LLM calls. The Composer analyzes a
  repo anchor's key events and produces a prompt the calling agent uses
  to generate scenarios, or returns existing library scenarios when no
  anchor is provided.
  """

  require Logger

  alias Prism.Scenario.{Library, Validator}
  alias Prism.Benchmark.CLCategories

  @doc """
  Compose scenarios from a repo anchor.

  Returns `{:ok, %{prompt: ..., status: "prompt_ready", ...}}` with a
  scenario-generation prompt the agent should run against an LLM, then
  store results via `compose(action: "scenarios")`.
  """
  @spec compose(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def compose(anchor, opts \\ [])
  def compose(nil, _opts), do: {:error, :nil_anchor}

  def compose(anchor, opts) do
    count = Keyword.get(opts, :count, 10)
    focus_dimensions = Keyword.get(opts, :focus_dimensions, [])
    focus_domains = Keyword.get(opts, :focus_domains, [])
    generator_model = Keyword.get(opts, :generator_model, "claude-sonnet-4-20250514")

    key_events = anchor.key_events || []

    if key_events == [] do
      {:error, :no_key_events}
    else
      prompt = build_compose_prompt(anchor, key_events, count, focus_dimensions, focus_domains)

      Logger.info(
        "[PRISM] Composer: generating prompt for #{count} scenarios from anchor #{anchor.id}"
      )

      {:ok,
       %{
         prompt: prompt,
         model: generator_model,
         anchor_id: anchor.id,
         target_count: count,
         focus_dimensions: focus_dimensions,
         focus_domains: focus_domains,
         status: "prompt_ready"
       }}
    end
  end

  # --- Internal ---

  defp build_compose_prompt(anchor, key_events, count, focus_dimensions, focus_domains) do
    all_dims = CLCategories.dimension_keys() |> Enum.map(&to_string/1)

    dim_focus =
      case focus_dimensions do
        [] -> "Cover all 9 CL dimensions evenly: #{Enum.join(all_dims, ", ")}"
        dims -> "Prioritize these dimensions: #{Enum.join(dims, ", ")} (but include others too)"
      end

    domain_focus =
      case focus_domains do
        [] -> "Domain: #{anchor.domain || "code"}"
        doms -> "Focus on domains: #{Enum.join(doms, ", ")}"
      end

    existing = Library.list()
    coverage = Validator.validate_coverage(existing)
    gap_text = format_gaps(coverage.gaps)

    events_text =
      key_events
      |> Enum.take(20)
      |> Enum.map_join("\n", fn event ->
        "- [#{event["type"] || Map.get(event, :type)}] #{event["description"] || Map.get(event, :description)} (#{event["commit"] || Map.get(event, :commit) |> String.slice(0..7)})"
      end)

    """
    You are a PRISM scenario composer. Generate #{count} CL evaluation scenarios
    based on the following repository events.

    ## Repository
    URL: #{anchor.repo_url}
    Domain: #{anchor.domain || "code"}
    Total commits analyzed: #{length(key_events)}

    ## Key Events
    #{events_text}

    ## Coverage Priorities
    #{dim_focus}
    #{domain_focus}

    ## Current Gaps
    #{if gap_text == "", do: "No coverage gaps detected.", else: gap_text}

    ## Existing Scenarios
    #{length(existing)} scenarios already in the library.

    ## Instructions
    Generate #{count} scenario objects as a JSON array. Each scenario must have:
    - "kind": "anchor" (tests known facts) or "frontier" (tests edge cases)
    - "domain": one of [code, research, operations, business, personal]
    - "difficulty": 1-5
    - "persona": {"name": "...", "role": "...", "context": "..."}
    - "sessions": array of session objects, each with turns containing cl_challenges
    - "cl_challenges": {"description": "...", "dimensions": ["dim1", "dim2"]}

    Each turn's cl_challenge must have:
    - "dimension": one of #{inspect(all_dims)}
    - "ground_truth": the verifiable correct answer

    Return JSON array of scenario objects.
    """
  end

  defp format_gaps(gaps) do
    Enum.map_join(gaps, "\n", fn gap ->
      case gap.type do
        :dimension_gap ->
          "- Dimension gap: #{gap.dimension} (#{Float.round(gap.current_ratio * 100, 1)}% coverage)"

        :domain_gap ->
          "- Domain gap: #{gap.domain} (#{gap.current_count}/#{gap.required_count} scenarios)"

        _ ->
          "- #{inspect(gap)}"
      end
    end)
  end
end
