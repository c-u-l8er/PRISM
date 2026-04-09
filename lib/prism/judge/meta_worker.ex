defmodule Prism.Judge.MetaWorker do
  @moduledoc """
  Layer 3: Meta-judge that evaluates Layer 2 judgments.

  Scores each L2 judgment on three axes:
  - Consistency (0-1): Same evidence → same score?
  - Evidence grounding (0-1): Does score match cited transcript evidence?
  - Rubric compliance (0-1): Did the judge follow the rubric?

  Critical: MUST use a different model family than the L2 judge.
  """

  require Logger

  alias Prism.MetaJudgment

  @doc """
  Meta-judge a Layer 2 judgment.

  Validates cross-model requirement and evaluates the judgment.
  """
  @spec meta_judge(map(), map(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def meta_judge(judgment, transcript, meta_judge_model, _opts \\ []) do
    l2_model = judgment.judge_model || Map.get(judgment, :judge_model)

    # Enforce cross-model family requirement
    if MetaJudgment.same_model_family?(l2_model, meta_judge_model) do
      {:error,
       {:same_model_family,
        "Meta-judge (#{meta_judge_model}) must use different model family than L2 judge (#{l2_model})"}}
    else
      run_meta_judgment(judgment, transcript, meta_judge_model)
    end
  end

  @doc """
  Meta-judge all Layer 2 judgments for a run.
  """
  @spec meta_judge_batch([map()], [map()], String.t(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def meta_judge_batch(judgments, transcripts, meta_judge_model, opts \\ []) do
    transcript_map = Map.new(transcripts, fn t -> {t.id || Map.get(t, :id), t} end)

    results =
      Enum.map(judgments, fn judgment ->
        transcript_id = judgment.transcript_id || Map.get(judgment, :transcript_id)
        transcript = Map.get(transcript_map, transcript_id)

        if transcript do
          meta_judge(judgment, transcript, meta_judge_model, opts)
        else
          {:error, {:transcript_not_found, transcript_id}}
        end
      end)

    successes = Enum.filter(results, &match?({:ok, _}, &1)) |> Enum.map(fn {:ok, m} -> m end)
    {:ok, successes}
  end

  # --- Internal ---

  defp run_meta_judgment(judgment, transcript, meta_judge_model) do
    prompt = build_meta_prompt(judgment, transcript)

    Logger.info(
      "[PRISM] L3 meta-judging: judgment=#{judgment.dimension}, model=#{meta_judge_model}"
    )

    # Return the prompt for the agent to evaluate externally.
    {:ok,
     %{
       prompt: prompt,
       meta_judge_model: meta_judge_model,
       status: "prompt_ready"
     }}
  end

  defp build_meta_prompt(judgment, transcript) do
    """
    You are a PRISM Layer 3 meta-judge. Your job is to evaluate the QUALITY
    of a Layer 2 judgment — not to re-judge the transcript yourself.

    ## Layer 2 Judgment Under Review
    Dimension: #{judgment.dimension}
    Judge model: #{judgment.judge_model}
    Composite score: #{judgment.composite_score}
    Challenge scores: #{Jason.encode!(judgment.challenge_scores)}
    Unprompted score: #{judgment.unprompted_score}
    Unprompted evidence: #{judgment.unprompted_evidence || "none"}

    ## Original Transcript (for reference)
    #{Jason.encode!(transcript.sessions, pretty: true)}

    ## Evaluate on Three Axes

    ### 1. Consistency (0.0 - 1.0)
    Would similar evidence in a different transcript produce a similar score?
    Are the challenge scores internally consistent with each other?

    ### 2. Evidence Grounding (0.0 - 1.0)
    Does the cited evidence actually appear in the transcript?
    Does the evidence support the assigned score?
    Are there relevant transcript segments the judge missed?

    ### 3. Rubric Compliance (0.0 - 1.0)
    Did the judge follow the dimension's scoring criteria?
    Are the 0/0.5/1 thresholds applied correctly?
    Is the 70/30 challenge/unprompted weighting respected?

    ## Return JSON:
    {
      "consistency_score": 0.X,
      "evidence_grounding_score": 0.X,
      "rubric_compliance_score": 0.X,
      "composite_score": 0.X,
      "recommendation": "accept|flag|reject",
      "reasoning": "Brief explanation of the meta-judgment..."
    }
    """
  end

  @doc """
  Parse a raw LLM meta-judgment response into a structured map.

  Called by the agent after running the L3 prompt returned by `meta_judge/4`.
  """
  @spec parse_meta_response(map(), String.t()) :: map()
  def parse_meta_response(response, meta_judge_model) do
    consistency = Map.get(response, "consistency_score", 0.5)
    grounding = Map.get(response, "evidence_grounding_score", 0.5)
    compliance = Map.get(response, "rubric_compliance_score", 0.5)

    composite =
      Map.get(response, "composite_score") ||
        MetaJudgment.compute_composite(consistency, grounding, compliance)

    recommendation =
      Map.get(response, "recommendation") ||
        MetaJudgment.recommendation_from_score(composite)

    %{
      meta_judge_model: meta_judge_model,
      consistency_score: consistency,
      evidence_grounding_score: grounding,
      rubric_compliance_score: compliance,
      composite_score: composite,
      recommendation: recommendation,
      reasoning: Map.get(response, "reasoning"),
      raw_response: response
    }
  end
end
