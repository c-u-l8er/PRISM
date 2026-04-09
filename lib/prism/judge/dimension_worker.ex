defmodule Prism.Judge.DimensionWorker do
  @moduledoc """
  Layer 2: Per-dimension transcript judge.

  Analyzes a full interaction transcript for one CL dimension,
  scoring challenge-specific criteria (70%) and unprompted behavior (30%).
  """

  require Logger

  alias Prism.Judge.Rubrics
  alias Prism.Judgment

  @doc """
  Judge a transcript for a specific CL dimension.

  Returns a judgment map ready for persistence.
  """
  @spec judge(map() | nil, String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def judge(transcript, dimension, judge_model, opts \\ [])
  def judge(nil, _dimension, _judge_model, _opts), do: {:error, :nil_transcript}

  def judge(transcript, dimension, judge_model, opts) do
    rubric = Rubrics.get(dimension)

    if match?(%{error: _}, rubric) do
      {:error, {:unknown_dimension, dimension}}
    else
      domain = Keyword.get(opts, :domain, "code")
      challenges = extract_challenges(transcript, dimension)
      prompt = build_judge_prompt(transcript, dimension, rubric, challenges, domain)

      Logger.info("[PRISM] L2 judging: dimension=#{dimension}, model=#{judge_model}")

      # Return the prompt for the agent to evaluate externally.
      # The agent calls this to get the prompt, runs the LLM, then stores the result.
      {:ok,
       %{
         prompt: prompt,
         dimension: dimension,
         judge_model: judge_model,
         status: "prompt_ready"
       }}
    end
  end

  @doc """
  Judge all 9 dimensions for a transcript.
  Returns a list of judgment maps.
  """
  @spec judge_all(map(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def judge_all(transcript, judge_model, opts \\ []) do
    results =
      Judgment.valid_dimensions()
      |> Enum.map(fn dim ->
        case judge(transcript, dim, judge_model, opts) do
          {:ok, judgment} -> {:ok, judgment}
          {:error, reason} -> {:error, {dim, reason}}
        end
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      judgments = Enum.map(results, fn {:ok, j} -> j end)
      {:ok, judgments}
    else
      {:error, {:partial_failure, errors}}
    end
  end

  # --- Internal ---

  defp build_judge_prompt(transcript, dimension, rubric, challenges, domain) do
    domain_note = get_in(rubric, [:domain_notes, String.to_existing_atom(domain)]) || ""

    """
    You are a PRISM Layer 2 judge evaluating continual learning behavior.

    ## Your Task
    Analyze this interaction transcript for the **#{dimension}** dimension.

    ## Dimension: #{dimension}
    #{rubric.description}

    ## Scoring Criteria
    - 1.0: #{rubric.challenge_criteria.score_1_0}
    - 0.5: #{rubric.challenge_criteria.score_0_5}
    - 0.0: #{rubric.challenge_criteria.score_0_0}

    ## Domain Context (#{domain})
    #{domain_note}

    ## CL Challenges to Evaluate
    #{Jason.encode!(challenges, pretty: true)}

    ## Unprompted Behavior Indicators (look for these)
    #{Enum.map_join(rubric.unprompted_indicators, "\n", &("- " <> &1))}

    ## Transcript
    #{Jason.encode!(transcript.sessions, pretty: true)}

    ## Instructions
    Score each challenge (0.0 to 1.0) with evidence from the transcript.
    Then score unprompted behavior (0.0 to 1.0).

    Return JSON:
    {
      "challenge_scores": [
        {
          "challenge_id": "...",
          "score": 0.X,
          "evidence": "Specific transcript evidence...",
          "ground_truth_verified": true/false
        }
      ],
      "challenge_composite": 0.X,
      "unprompted_score": 0.X,
      "unprompted_evidence": "Description of unprompted CL behavior observed...",
      "composite_score": 0.X
    }
    """
  end

  defp extract_challenges(transcript, dimension) do
    # Extract CL challenges from the scenario that match this dimension
    sessions = Map.get(transcript, :sessions) || Map.get(transcript, "sessions") || []

    sessions
    |> Enum.flat_map(fn session ->
      turns = Map.get(session, "turns") || Map.get(session, :turns) || []

      Enum.filter(turns, fn turn ->
        challenge = Map.get(turn, "cl_challenge") || Map.get(turn, :cl_challenge)

        if challenge do
          dim = Map.get(challenge, "dimension") || Map.get(challenge, :dimension)
          to_string(dim) == to_string(dimension)
        else
          false
        end
      end)
    end)
    |> Enum.map(fn turn ->
      Map.get(turn, "cl_challenge") || Map.get(turn, :cl_challenge)
    end)
  end

  @doc """
  Parse a raw LLM judgment response into a structured map.

  Called by the agent after running the L2 prompt returned by `judge/4`.
  """
  @spec parse_judgment(map(), String.t(), String.t()) :: map()
  def parse_judgment(response, dimension, judge_model) do
    challenge_composite =
      Map.get(response, "challenge_composite") ||
        compute_challenge_composite(Map.get(response, "challenge_scores", []))

    unprompted = Map.get(response, "unprompted_score", 0.0)

    composite =
      Map.get(response, "composite_score") ||
        Judgment.compute_composite(challenge_composite, unprompted)

    %{
      dimension: dimension,
      judge_model: judge_model,
      challenge_scores: Map.get(response, "challenge_scores", []),
      challenge_composite: challenge_composite,
      unprompted_score: unprompted,
      unprompted_evidence: Map.get(response, "unprompted_evidence"),
      composite_score: composite,
      rubric_version: Rubrics.version(),
      raw_response: response
    }
  end

  @doc false
  @spec compute_challenge_composite([map()]) :: float()
  def compute_challenge_composite(scores) when is_list(scores) do
    values = Enum.map(scores, fn s -> Map.get(s, "score", 0.0) end)

    case values do
      [] -> 0.0
      vals -> Enum.sum(vals) / length(vals)
    end
  end
end
