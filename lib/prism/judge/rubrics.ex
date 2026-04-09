defmodule Prism.Judge.Rubrics do
  @moduledoc """
  Dimension-specific rubric templates for Layer 2 judges.

  Each rubric provides structured scoring criteria for a CL dimension,
  including challenge-specific criteria (70% weight) and unprompted
  behavior indicators (30% weight).
  """

  @rubric_version "v2.0"

  @doc "Returns the rubric version string."
  def version, do: @rubric_version

  @doc "Get the rubric template for a specific dimension."
  @spec get(String.t()) :: map()
  def get("stability"), do: stability_rubric()
  def get("plasticity"), do: plasticity_rubric()
  def get("knowledge_update"), do: knowledge_update_rubric()
  def get("temporal"), do: temporal_rubric()
  def get("consolidation"), do: consolidation_rubric()
  def get("epistemic_awareness"), do: epistemic_awareness_rubric()
  def get("transfer"), do: transfer_rubric()
  def get("forgetting"), do: forgetting_rubric()
  def get("feedback"), do: feedback_rubric()
  def get(_), do: %{error: "Unknown dimension"}

  @doc "Get all rubrics."
  @spec all() :: map()
  def all do
    Prism.Judgment.valid_dimensions()
    |> Enum.map(fn dim -> {dim, get(dim)} end)
    |> Map.new()
  end

  defp stability_rubric do
    %{
      dimension: "stability",
      version: @rubric_version,
      description: "Retaining old knowledge when new arrives",
      challenge_criteria: %{
        scoring_difficulty: "Easy — binary fact recall",
        expected_agreement: 0.95,
        score_1_0: "Correctly recalls original information after intervening updates",
        score_0_5: "Partially recalls — correct topic but wrong details, or low confidence",
        score_0_0: "Cannot recall or retrieves wrong information"
      },
      unprompted_indicators: [
        "Proactively references older knowledge without being asked",
        "Maintains consistent representations across sessions",
        "Distinguishes between old and new without confusion"
      ],
      domain_notes: %{
        code: "Tests retention of API signatures, module structures after refactors",
        medical: "Tests retention of patient history after new diagnoses",
        business: "Tests retention of prior strategy decisions after market changes"
      }
    }
  end

  defp plasticity_rubric do
    %{
      dimension: "plasticity",
      version: @rubric_version,
      description: "Speed and accuracy of learning new information",
      challenge_criteria: %{
        scoring_difficulty: "Easy-Medium",
        expected_agreement: 0.90,
        score_1_0: "Immediately incorporates and correctly uses new information",
        score_0_5: "Learns new information but with delay or partial accuracy",
        score_0_0: "Fails to incorporate new information"
      },
      unprompted_indicators: [
        "Applies newly learned patterns to subsequent queries",
        "Updates internal representations without explicit instruction",
        "Shows learning curve improvement within a session"
      ],
      domain_notes: %{
        code: "Tests learning new dependencies, conventions from commits",
        medical: "Tests incorporating new treatment guidelines",
        business: "Tests absorbing new competitive intelligence"
      }
    }
  end

  defp knowledge_update_rubric do
    %{
      dimension: "knowledge_update",
      version: @rubric_version,
      description: "Detecting and resolving conflicts between old and new",
      challenge_criteria: %{
        scoring_difficulty: "Medium — subtle contradictions",
        expected_agreement: 0.85,
        score_1_0: "Correctly identifies contradiction and updates to new information",
        score_0_5: "Identifies change but retains both old and new without resolution",
        score_0_0: "Returns outdated information or fails to detect contradiction"
      },
      unprompted_indicators: [
        "Flags contradictions proactively",
        "Explains what changed and why",
        "Handles cascade updates (A depends on B, B changed)"
      ],
      domain_notes: %{
        code: "Tests library swaps, API changes, config updates",
        medical: "Tests guideline revisions, drug interaction updates",
        business: "Tests strategy pivots, competitive landscape changes"
      }
    }
  end

  defp temporal_rubric do
    %{
      dimension: "temporal",
      version: @rubric_version,
      description: "Knowing when things happened and what's current",
      challenge_criteria: %{
        scoring_difficulty: "Medium — date edge cases",
        expected_agreement: 0.85,
        score_1_0: "Correctly orders events and identifies current state",
        score_0_5: "Knows recency but confused about exact ordering",
        score_0_0: "Cannot distinguish old from new or orders events incorrectly"
      },
      unprompted_indicators: [
        "References temporal context ('as of commit X', 'since the refactor')",
        "Distinguishes 'current' from 'historical' state",
        "Tracks multi-version evolution of the same entity"
      ],
      domain_notes: %{
        code: "Tests commit ordering, version awareness, state-at-time-T queries",
        medical: "Tests treatment timeline awareness, symptom progression",
        business: "Tests market event ordering, quarterly data evolution"
      }
    }
  end

  defp consolidation_rubric do
    %{
      dimension: "consolidation",
      version: @rubric_version,
      description: "Compressing episodes into insights over time",
      challenge_criteria: %{
        scoring_difficulty: "Hard — summary quality",
        expected_agreement: 0.70,
        score_1_0: "Produces accurate high-level insight from many data points",
        score_0_5: "Summarizes but misses key patterns or over-generalizes",
        score_0_0: "Cannot synthesize — only returns individual facts"
      },
      unprompted_indicators: [
        "Spontaneously offers pattern summaries",
        "Recognizes repeated structures across different contexts",
        "Builds hierarchical understanding (facts → patterns → principles)"
      ],
      domain_notes: %{
        code: "Tests architecture extraction from file-level facts",
        medical: "Tests diagnostic pattern recognition from case history",
        business: "Tests strategic insight extraction from operational data"
      }
    }
  end

  defp epistemic_awareness_rubric do
    %{
      dimension: "epistemic_awareness",
      version: @rubric_version,
      description: "Knowing what you don't know, calibrated confidence",
      challenge_criteria: %{
        scoring_difficulty: "Hard — calibration is subjective",
        expected_agreement: 0.75,
        score_1_0:
          "Correctly identifies knowledge boundaries and expresses calibrated uncertainty",
        score_0_5: "Sometimes uncertain when should be confident, or vice versa",
        score_0_0: "Confidently wrong or unable to express uncertainty"
      },
      unprompted_indicators: [
        "Says 'I don't know' or 'I'm not sure' when appropriate",
        "Distinguishes between 'not in my context' and 'contradictory evidence'",
        "Expresses graduated confidence levels"
      ],
      domain_notes: %{
        code: "Tests awareness of uningested files, incomplete context",
        medical: "Tests uncertainty about unconfirmed diagnoses",
        business: "Tests acknowledgment of incomplete market data"
      }
    }
  end

  defp transfer_rubric do
    %{
      dimension: "transfer",
      version: @rubric_version,
      description: "Knowledge from domain A improving domain B",
      challenge_criteria: %{
        scoring_difficulty: "Very Hard — open-ended",
        expected_agreement: 0.65,
        score_1_0: "Recognizes and applies cross-context pattern",
        score_0_5: "Partial transfer — recognizes similarity but doesn't apply",
        score_0_0: "Treats each context as independent"
      },
      unprompted_indicators: [
        "References patterns from other modules/domains",
        "Suggests applying known solutions to new problems",
        "Draws analogies across different contexts"
      ],
      domain_notes: %{
        code: "Tests pattern recognition across modules (auth pattern → API pattern)",
        medical: "Tests cross-condition reasoning (drug interaction patterns)",
        business: "Tests cross-market analogies"
      }
    }
  end

  defp forgetting_rubric do
    %{
      dimension: "forgetting",
      version: @rubric_version,
      description: "Deliberate pruning, GDPR erasure, policy-based decay",
      challenge_criteria: %{
        scoring_difficulty: "Easy — binary presence check",
        expected_agreement: 0.92,
        score_1_0: "Successfully forgets requested information, verification shows absence",
        score_0_5: "Partially forgets — some traces remain or related info affected",
        score_0_0: "Fails to forget or cannot verify absence"
      },
      unprompted_indicators: [
        "Confirms deletion with appropriate evidence",
        "Handles cascade implications of forgetting",
        "Maintains audit trail of what was forgotten"
      ],
      domain_notes: %{
        code: "Tests deletion of specific code knowledge, config secrets",
        medical: "Tests GDPR erasure of patient data",
        business: "Tests removal of confidential competitive intelligence"
      }
    }
  end

  defp feedback_rubric do
    %{
      dimension: "feedback",
      version: @rubric_version,
      description: "Retrieval quality improving from downstream signals",
      challenge_criteria: %{
        scoring_difficulty: "Hard — learning curves",
        expected_agreement: 0.70,
        score_1_0: "Retrieval quality visibly improves after feedback",
        score_0_5: "Shows some improvement but inconsistent or delayed",
        score_0_0: "No observable change in retrieval after feedback"
      },
      unprompted_indicators: [
        "Adjusts retrieval ranking based on prior feedback",
        "Mentions learning from previous interactions",
        "Shows improved confidence calibration over time"
      ],
      domain_notes: %{
        code: "Tests whether unhelpful code retrieval is deprioritized",
        medical: "Tests whether treatment feedback improves future suggestions",
        business: "Tests whether outcome feedback improves forecasting"
      }
    }
  end
end
