defmodule Prism.Benchmark.CLCategories do
  @moduledoc """
  The 9 Continual Learning evaluation dimensions.

  Each category defines:
  - Weight in the composite score
  - Question generation templates
  - Difficulty levels 1-5
  - Academic grounding (which published benchmarks inform this)
  - Scoring rubric for the LLM judge

  These specs are fed to the LLM generator in Phase A to produce
  benchmark questions, and to the LLM judge in Phase C to score answers.
  """

  @categories [
    %{
      id: :stability,
      name: "Stability (Anti-Forgetting)",
      weight: 0.20,
      description: """
      Can the system retain previously learned knowledge when new information
      arrives? Does it avoid catastrophic forgetting?
      """,
      question_templates: [
        %{
          type: :retention_after_update,
          pattern: "Ingest 10 facts. Add 10 new facts. Query for original facts.",
          scoring: "Score = fraction of original facts correctly recalled"
        },
        %{
          type: :stability_under_load,
          pattern: "Ingest fact A. Then ingest 100 unrelated facts. Query for A.",
          scoring: "Binary: 1 if A is recalled correctly, 0 otherwise"
        },
        %{
          type: :preference_persistence,
          pattern: "User states preference P. 50 interactions later, query for P.",
          scoring: "1 if P recalled, 0.5 if partially recalled, 0 if lost"
        }
      ],
      difficulty_levels: %{
        1 => "Recall after 5 intervening facts",
        2 => "Recall after 50 intervening facts",
        3 => "Recall after 200 intervening facts across sessions",
        4 => "Recall of nuanced reasoning, not just atomic facts",
        5 => "Recall under adversarial distraction (similar-but-different facts)"
      },
      external_benchmarks: ["BEAM (10M scale)", "TRACE (General Ability Delta)", "LongMemEval"]
    },
    %{
      id: :plasticity,
      name: "Plasticity (New Knowledge Acquisition)",
      weight: 0.18,
      description: """
      How quickly and accurately can the system incorporate genuinely new
      information? Does it resist intransigence?
      """,
      question_templates: [
        %{
          type: :immediate_learning,
          pattern: "Teach the system a new fact. Immediately query for it.",
          scoring: "1 if correctly learned, 0 otherwise"
        },
        %{
          type: :rule_learning,
          pattern: "Define a new rule ('always respond in JSON'). Test compliance.",
          scoring: "1 if rule followed, 0.5 if partially, 0 if ignored"
        },
        %{
          type: :preference_update,
          pattern: "User changes preference from X to Y. Query uses old context.",
          scoring: "1 if Y is used, 0 if X persists"
        }
      ],
      difficulty_levels: %{
        1 => "Simple fact acquisition",
        2 => "Rule/procedure acquisition",
        3 => "Preference change with conflicting prior context",
        4 => "Multi-step procedure learned from examples",
        5 => "Implicit preference inferred from behavior, not stated"
      },
      external_benchmarks: ["MemoryBench", "Evo-Memory", "MemoryAgentBench (TTL)"]
    },
    %{
      id: :knowledge_update,
      name: "Knowledge Update & Contradiction Resolution",
      weight: 0.15,
      description: """
      When new information contradicts old information, does the system
      detect the conflict, resolve it correctly, and propagate the change?
      """,
      question_templates: [
        %{
          type: :simple_contradiction,
          pattern: "Session 1: 'I live in NYC'. Session 5: 'I moved to Austin'. Query: 'Where do I live?'",
          scoring: "1 for Austin, 0.5 if both mentioned with Austin as current, 0 for NYC"
        },
        %{
          type: :cascade_update,
          pattern: "A depends on B depends on C. Update C. Query for A.",
          scoring: "1 if A reflects updated C, 0 if stale"
        },
        %{
          type: :temporal_supersession,
          pattern: "Fact stated at T1, contradicted at T2 > T1. Query at T3 > T2.",
          scoring: "1 for T2 version, 0 for T1 version"
        }
      ],
      difficulty_levels: %{
        1 => "Explicit contradiction, same session",
        2 => "Explicit contradiction, cross-session",
        3 => "Implicit contradiction requiring inference",
        4 => "Multi-hop cascade (A→B→C, update A)",
        5 => "Semantic contradiction with no lexical overlap"
      },
      external_benchmarks: [
        "BEAM (contradiction resolution)",
        "LongMemEval (knowledge update track)",
        "GraphMemBench (belief revision)",
        "MemoryAgentBench (conflict resolution)"
      ]
    },
    %{
      id: :consolidation,
      name: "Memory Consolidation & Abstraction",
      weight: 0.12,
      description: """
      Does the system compress, merge, or abstract knowledge over time?
      Can it go from raw episodes to structured insights?
      """,
      question_templates: [
        %{
          type: :summarization,
          pattern: "Ingest 50 sessions about project X. Query: 'Give me a comprehensive summary.'",
          scoring: "Scored on completeness, accuracy, and compression ratio"
        },
        %{
          type: :pattern_recognition,
          pattern: "Ingest 20 bug reports. Query: 'What's the most common failure pattern?'",
          scoring: "1 if pattern correctly identified, 0.5 for related but imprecise"
        },
        %{
          type: :frequency_awareness,
          pattern: "Mention topic A 15 times, topic B 3 times. Query: 'What do we discuss most?'",
          scoring: "1 if A identified, 0 if B or other"
        }
      ],
      difficulty_levels: %{
        1 => "Summarize 5 short sessions",
        2 => "Summarize 20 sessions, identify key themes",
        3 => "Identify patterns across 50+ episodes",
        4 => "Abstract a rule from observed examples",
        5 => "Hierarchical consolidation: episodes → themes → insights → strategy"
      },
      external_benchmarks: [
        "BEAM (summarization dimension)",
        "MemBench (reflective memory)",
        "MemoryAgentBench (LRU)"
      ]
    },
    %{
      id: :temporal,
      name: "Temporal Reasoning",
      weight: 0.10,
      description: """
      Can the system reason about when things happened, in what order,
      and what's current vs. outdated?
      """,
      question_templates: [
        %{
          type: :chronological_ordering,
          pattern: "Events A, B, C happened at T1, T2, T3. Query: 'What happened first?'",
          scoring: "1 for correct ordering, partial credit for partial ordering"
        },
        %{
          type: :relative_time,
          pattern: "User said X 'two weeks ago'. Query with date context.",
          scoring: "1 if correct date resolved, 0 otherwise"
        },
        %{
          type: :recency_awareness,
          pattern: "Old fact from 6 months ago vs. recent fact from yesterday. Query prefers recent.",
          scoring: "1 if recent fact prioritized, 0 if old fact returned"
        }
      ],
      difficulty_levels: %{
        1 => "Simple before/after with explicit dates",
        2 => "Relative dates ('last week', 'yesterday')",
        3 => "Session chronology ('which session came first?')",
        4 => "Temporal reasoning across multiple timelines",
        5 => "Implicit temporal ordering from context clues"
      },
      external_benchmarks: [
        "LongMemEval (temporal reasoning track)",
        "BEAM (event ordering + temporal reasoning)",
        "TemporalWiki"
      ]
    },
    %{
      id: :transfer,
      name: "Cross-Domain Transfer",
      weight: 0.08,
      description: """
      Can knowledge from one domain improve performance on another?
      Does learning compound across contexts?
      """,
      question_templates: [
        %{
          type: :structural_transfer,
          pattern: "Teach auth patterns in Project A. Query about security in Project B.",
          scoring: "1 if structural similarity recognized and applied"
        },
        %{
          type: :analogical_transfer,
          pattern: "Explain concept X in domain A. Query: 'What's analogous in domain B?'",
          scoring: "Scored on relevance and accuracy of the analogy"
        },
        %{
          type: :procedural_transfer,
          pattern: "Teach a workflow in context A. Query: 'Apply similar workflow to context B.'",
          scoring: "1 if workflow adapted correctly, 0.5 if partially"
        }
      ],
      difficulty_levels: %{
        1 => "Same domain, different project",
        2 => "Related domains (frontend → backend)",
        3 => "Distant domains (code → business strategy)",
        4 => "Abstract structural transfer (graph topology)",
        5 => "Transfer of reasoning patterns, not just facts"
      },
      external_benchmarks: [
        "TRACE (cross-task transfer effects)",
        "MemoryBench (multi-domain coverage)",
        "Evo-Memory (cross-benchmark learning)"
      ]
    },
    %{
      id: :uncertainty,
      name: "Epistemic Awareness & Calibration",
      weight: 0.07,
      description: """
      Does the system know what it knows and what it doesn't?
      Can it quantify confidence and abstain when appropriate?
      """,
      question_templates: [
        %{
          type: :abstention,
          pattern: "Ask about information that was never ingested.",
          scoring: "1 if system abstains or says 'I don't know', 0 if confabulates"
        },
        %{
          type: :confidence_calibration,
          pattern: "Ask about well-supported fact vs. weakly-supported fact.",
          scoring: "Score on whether confidence correlates with evidence strength"
        },
        %{
          type: :gap_identification,
          pattern: "After ingesting partial information, ask 'What don't you know?'",
          scoring: "1 if gaps correctly identified, 0 if overconfident"
        }
      ],
      difficulty_levels: %{
        1 => "Obvious unknown (never mentioned topic)",
        2 => "Plausible but unmentioned (could guess, shouldn't)",
        3 => "Partially known (some evidence, not conclusive)",
        4 => "Conflicting evidence (should express uncertainty)",
        5 => "Meta-epistemic (identify what areas need investigation)"
      },
      external_benchmarks: [
        "SeekBench (epistemic calibration)",
        "LongMemEval (abstention track)",
        "BEAM (abstention dimension)",
        "AUQ framework"
      ]
    },
    %{
      id: :forgetting,
      name: "Intentional Forgetting & Pruning",
      weight: 0.05,
      description: """
      Can the system deliberately forget? Does it support soft, hard,
      policy-based, and compliance-driven forgetting?
      """,
      question_templates: [
        %{
          type: :selective_forget,
          pattern: "Ingest fact A. Request deletion. Query for A.",
          scoring: "1 if A is no longer retrievable, 0 if still returned"
        },
        %{
          type: :policy_pruning,
          pattern: "Ingest 100 facts with varying importance. Trigger pruning. Query for low-importance facts.",
          scoring: "1 if low-importance pruned, high-importance retained"
        },
        %{
          type: :gdpr_erasure,
          pattern: "Ingest personal data. Request GDPR erasure. Verify complete deletion.",
          scoring: "1 if fully erased with audit trail, 0 if any trace remains"
        }
      ],
      difficulty_levels: %{
        1 => "Delete a single fact",
        2 => "Cascade delete (fact + all derived knowledge)",
        3 => "Policy-based pruning (LRU + importance scoring)",
        4 => "Partial forget (hide from retrieval but keep for audit)",
        5 => "GDPR Article 17 full erasure with provenance audit"
      },
      external_benchmarks: [
        "MemoryAgentBench (selective forgetting)",
        "GraphMemBench (intentional forgetting phases)"
      ]
    },
    %{
      id: :feedback,
      name: "Outcome-Driven Self-Correction",
      weight: 0.05,
      description: """
      Does the system learn from the outcomes of its own retrievals?
      Does retrieval quality improve from downstream reward signals?
      """,
      question_templates: [
        %{
          type: :retrieval_feedback,
          pattern: "System retrieves context, answers incorrectly. Provide 'unhelpful' signal. Ask again.",
          scoring: "1 if different (better) context retrieved on retry"
        },
        %{
          type: :ranking_adjustment,
          pattern: "Over 10 queries, consistently mark one retrieved source as unhelpful. Check if it drops in ranking.",
          scoring: "Score on ranking change magnitude"
        },
        %{
          type: :positive_reinforcement,
          pattern: "Mark a retrieval as 'very helpful'. Check if similar queries surface similar context.",
          scoring: "1 if positive signal propagates to related queries"
        }
      ],
      difficulty_levels: %{
        1 => "Single negative feedback → immediate re-retrieval",
        2 => "Accumulated feedback over 5 queries → ranking shift",
        3 => "Feedback propagation to semantically similar queries",
        4 => "Conflicting feedback signals → resolution",
        5 => "Long-term Q-value convergence over 50+ feedback cycles"
      },
      external_benchmarks: [
        "MemoryBench (feedback-driven learning)",
        "Evo-Memory (cumulative improvement curves)"
      ]
    }
  ]

  @doc "Get all CL category specs"
  def all, do: @categories

  @doc "Get a single category by id"
  def get(id) when is_atom(id) do
    Enum.find(@categories, &(&1.id == id))
  end

  @doc "Get the default weight vector"
  def default_weights do
    Map.new(@categories, fn cat -> {cat.id, cat.weight} end)
  end

  @doc "Get all category IDs"
  def ids, do: Enum.map(@categories, & &1.id)

  @doc "Validate that weights sum to 1.0"
  def validate_weights(weights) do
    sum = weights |> Map.values() |> Enum.sum()
    if abs(sum - 1.0) < 0.01, do: :ok, else: {:error, "Weights sum to #{sum}, expected 1.0"}
  end
end
