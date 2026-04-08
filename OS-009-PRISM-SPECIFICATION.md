# PRISM — Protocol for Rating Iterative System Memory

## OpenSentience Specification OS-009-PRISM v0.1

**A self-improving continual learning evaluation engine for AI agent memory systems.**

PRISM takes what looks like a single "memory benchmark score" and reveals
the 9-dimensional CL spectrum underneath. It generates its own benchmarks,
executes them against any memory system via MCP, judges the results, identifies
gaps, and generates harder questions targeting those gaps — in a perpetual
self-improving loop.

**Stack:** Elixir 1.17+ / OTP 27 / Postgres / Fly.io
**Protocol:** MCP (Model Context Protocol) with 29 tools
**License:** Apache 2.0
**Canonical URL:** opensentience.org/prism

---

## Table of Contents

1. [Motivation & Background](#1-motivation--background)
2. [The 9 CL Dimensions](#2-the-9-cl-dimensions)
3. [Architecture Overview](#3-architecture-overview)
4. [Phase A: Generate](#4-phase-a-generate)
5. [Phase B: Execute](#5-phase-b-execute)
6. [Phase C: Judge & Score](#6-phase-c-judge--score)
7. [The Meta-Loop (CL-on-CL)](#7-the-meta-loop-cl-on-cl)
8. [Data Model (Postgres)](#8-data-model-postgres)
9. [MCP Tool Surface (29 tools)](#9-mcp-tool-surface-29-tools)
10. [CL Category Specifications](#10-cl-category-specifications)
11. [Scoring System Design](#11-scoring-system-design)
12. [External Benchmark Integration](#12-external-benchmark-integration)
13. [Deployment (Fly.io)](#13-deployment-flyio)
14. [Observability & Telemetry](#14-observability--telemetry)
15. [Known Risks & Mitigations](#15-known-risks--mitigations)
16. [Predicted System Scores](#16-predicted-system-scores)
17. [Implementation Roadmap](#17-implementation-roadmap)

---

## 1. Motivation & Background

### The Problem

No existing benchmark covers all aspects of continual learning for agent
memory systems. The current landscape:

| Benchmark | What It Tests | What It Misses |
|-----------|--------------|----------------|
| LongMemEval (ICLR 2025) | Retrieval, temporal, knowledge update, abstention | Consolidation, transfer, feedback, forgetting |
| BEAM (ICLR 2026) | 10 memory abilities at 10M token scale | Intentional forgetting, outcome feedback, cross-domain transfer |
| MemoryAgentBench (ICLR 2026) | Retrieval, test-time learning, conflict resolution, selective forgetting | Consolidation, transfer, uncertainty, feedback |
| MemoryBench | Feedback-driven CL, multi-domain | Temporal, uncertainty, forgetting |
| Evo-Memory | Streaming cumulative improvement | Forgetting, uncertainty, consolidation |
| TRACE (ICLR 2025) | Weight-level catastrophic forgetting | All agent memory dimensions |
| GraphMemBench v2 | Belief revision, GDPR forgetting, κ-topology | Transfer, feedback, scale stress |
| SeekBench | Epistemic calibration | Everything else |

Existing benchmarks cover ~77% of the CL evaluation space. The remaining
gaps: consolidation/abstraction, cross-domain transfer, and closed-loop
retrieval feedback.

More importantly: all existing benchmarks are STATIC. They're designed once
and slowly saturate. PRISM is the first benchmark that improves itself.

### The Solution

PRISM is a three-phase loop:

```
Phase A (Generate) → Phase B (Execute) → Phase C (Judge)
       ↑                                        │
       └────────── Gap Analysis Feedback ────────┘
```

Each cycle produces a benchmark suite, runs it, scores results across 9 CL
dimensions, identifies gaps, and generates harder questions targeting those
gaps. Over time, the suite converges toward the hardest, most discriminating
questions.

### Why This Architecture

The LLM serves three roles:
1. **Generator** — produces benchmark questions from CL category specs
2. **Executor** — powers the memory systems under test
3. **Judge** — scores answers against rubrics

Different models are used for generation vs. judging to avoid self-bias.
External benchmark questions (BEAM, LongMemEval) serve as anchors that
break any self-referential loops.

---

## 2. The 9 CL Dimensions

Each dimension has a weight in the composite score, reflecting its importance
to continual learning. Weights sum to 1.0 and are configurable.

| # | Dimension | Weight | What It Tests |
|---|-----------|--------|---------------|
| 1 | **Stability** (Anti-Forgetting) | 0.20 | Retaining old knowledge when new arrives |
| 2 | **Plasticity** (New Acquisition) | 0.18 | Speed and accuracy of learning new information |
| 3 | **Knowledge Update** (Contradiction) | 0.15 | Detecting and resolving conflicts between old and new |
| 4 | **Consolidation** (Abstraction) | 0.12 | Compressing episodes into insights over time |
| 5 | **Temporal Reasoning** | 0.10 | Knowing when things happened and what's current |
| 6 | **Cross-Domain Transfer** | 0.08 | Knowledge from domain A improving domain B |
| 7 | **Epistemic Awareness** | 0.07 | Knowing what you don't know, calibrated confidence |
| 8 | **Intentional Forgetting** | 0.05 | Deliberate pruning, GDPR erasure, policy-based decay |
| 9 | **Outcome Feedback** | 0.05 | Retrieval quality improving from downstream signals |

### Academic Grounding

These dimensions are derived from:

- **Stability-plasticity dilemma** (Mermillod et al., 2013; Grossberg, 1982)
- **Backward/forward transfer** metrics (Lopez-Paz & Ranzato, 2017)
- **CL-for-LLMs survey** (Wang et al., ACM Computing Surveys 2025)
- **Complementary Learning Systems** theory (McClelland et al., 1995)
- **AGM belief revision** postulates (Alchourrón, Gärdenfors, Makinson, 1985)

### Scoring Reliability by Dimension

Based on analysis of LLM-as-judge agreement rates:

| Dimension | Scoring Difficulty | Expected Judge Agreement |
|-----------|-------------------|------------------------|
| Stability | Easy — binary fact recall | ~95% |
| Plasticity | Easy-Medium | ~90% |
| Knowledge Update | Medium — subtle contradictions | ~85% |
| Temporal | Medium — date edge cases | ~85% |
| Forgetting | Easy — binary presence check | ~92% |
| Uncertainty | Hard — calibration is subjective | ~75% |
| Consolidation | Hard — summary quality | ~70% |
| Transfer | Very Hard — open-ended | ~65% |
| Feedback | Hard — learning curves | ~70% |

The protocol MUST report confidence intervals, not just point estimates.
Systems within the error margin should be considered tied.

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    PRISM Engine                          │
│                  (Elixir/OTP on Fly.io)                 │
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐             │
│  │ Phase A  │→ │ Phase B  │→ │ Phase C  │             │
│  │ Generate │  │ Execute  │  │ Judge    │             │
│  └──────────┘  └──────────┘  └──────────┘             │
│       ↑                           │                     │
│       └──── Gap Analysis ─────────┘                     │
│                                                         │
│  ┌──────────────────────────────────────┐              │
│  │         MCP Tool Surface             │              │
│  │         29 tools via stdio/SSE       │              │
│  └──────────────────────────────────────┘              │
│                                                         │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐         │
│  │ Postgres  │  │ LLM APIs  │  │ Telemetry │         │
│  │ (Fly.io)  │  │ (Anthropic│  │ (metrics) │         │
│  │           │  │  OpenAI   │  │           │         │
│  │           │  │  Google)  │  │           │         │
│  └───────────┘  └───────────┘  └───────────┘         │
└─────────────────────────────────────────────────────────┘
         │              │              │
    ┌────┴────┐   ┌────┴────┐   ┌────┴────┐
    │Graphon- │   │Super-   │   │Mem0     │  ... any MCP
    │omous    │   │memory   │   │         │     system
    └─────────┘   └─────────┘   └─────────┘
```

### OTP Supervision Tree

```
Prism.Supervisor
├── Prism.Repo                    # Ecto/Postgres
├── Prism.Cycle.Manager           # Orchestrates A→B→C loop (GenServer)
├── Prism.Runner.Pool             # Concurrent test execution (DynamicSupervisor)
│   ├── Prism.Runner.Worker       # Individual test runner (Task)
│   ├── Prism.Runner.Worker
│   └── ...
├── Prism.MCP.Server              # MCP protocol handler (GenServer)
├── Prism.Leaderboard.Cache       # ETS-backed leaderboard cache
└── Prism.Telemetry               # Metrics and observability
```

---

## 4. Phase A: Generate

### Overview

The LLM generator reads the 9 CL category specs (including question
templates, difficulty levels, and academic grounding) and produces:

For each question:
- `question_text` — the question to ask the memory system
- `expected_answer` — the correct/ideal answer
- `rubric` — JSON scoring criteria for the LLM judge (0-1 scale)
- `cl_categories` — which CL dimensions this tests, with relative weights
- `difficulty` — 1-5 scale
- `requires_state` — whether prior ingestion is needed
- `ingestion_context` — if requires_state, what sessions to ingest first

### Generation Prompt Structure

```
System: You are PRISM, a benchmark designer for Continual Learning
evaluation of AI agent memory systems.

Context:
- 9 CL dimensions with specs (provided)
- Gap analysis from prior cycle (if cycle > 1)
- Saturated questions to avoid (if cycle > 1)
- Target difficulty distribution

Task: Generate {N} benchmark questions.

Constraints:
- Each question must test at least one CL dimension
- Target distribution matches the weight vector
- Difficulty distribution: 20% level 1-2, 50% level 3, 30% level 4-5
- Ingestion context must be realistic multi-session dialogue
- Rubrics must be unambiguous with clear 0/0.5/1 criteria
```

### Validation Pass

A DIFFERENT model validates each generated question:

1. Does it actually test the claimed CL dimensions?
2. Is the difficulty rating accurate?
3. Is the rubric clear and unambiguous?
4. Is the expected answer correct?
5. Is the question discriminating (would different systems score differently)?

Questions scoring below 0.6 on validation are rejected.

### Coverage Analysis

After validation, compute per-dimension coverage:
- Question count per dimension
- Mean difficulty per dimension
- Weight coverage (sum of question weights matching each dimension)

If any dimension has < 10% of its target coverage, trigger
additional generation focused on that dimension.

---

## 5. Phase B: Execute

### Overview

For each (suite × system × model) triple:

1. Connect to the memory system via MCP
2. Reset the system to clean state
3. For each question:
   a. Ingest the ingestion_context (if requires_state)
   b. Query the system with question_text
   c. Record: raw_answer, retrieval_context, ingestion_ms, retrieval_ms
4. Store all results with full trace

### MCP Adapter Behavior

```elixir
defmodule Prism.MCP.Adapter do
  @doc "Behavior that every memory system adapter must implement"

  @callback connect(config :: map()) :: {:ok, pid()} | {:error, term()}
  @callback ingest(pid(), sessions :: [map()]) :: {:ok, map()} | {:error, term()}
  @callback query(pid(), question :: String.t()) :: {:ok, answer :: String.t(), context :: map()} | {:error, term()}
  @callback reset(pid()) :: :ok | {:error, term()}
  @callback stats(pid()) :: map()
  @callback disconnect(pid()) :: :ok
end
```

### System Registration

Each memory system registers with:
- Name (e.g., "graphonomous")
- MCP endpoint (stdio command or SSE URL)
- Transport type (:stdio or :sse)
- Version string
- Supported tools (auto-discovered via tools/list)

### Specific Adapter Notes

**Graphonomous**: Native MCP with 29 tools. Use `store_node`, `store_edge`
for ingestion, `retrieve_context` for queries, `belief_revise` for
contradiction tests, `forget_node` for forgetting tests.

**Supermemory**: MCP server available. Use `supermemory_remember` for
ingestion, `supermemory_search` for queries, `supermemory_forget` for
forgetting tests.

**Mem0**: MCP available. Use `add` for ingestion, `search` for queries.

**MemPalace**: MCP available (19 tools). Use `mempalace_mine` for ingestion,
`mempalace_search` for queries.

**Zep/Graphiti**: REST API, needs MCP wrapper adapter.

### Matrix Execution

For a full evaluation:
```
Systems: [graphonomous, supermemory, mem0, mempalace, zep, mastra_om, omega]
Models:  [claude-sonnet-4-20250514, gpt-4o, gemini-2.0-flash]
Suite:   200 questions

Total runs: 7 × 3 = 21
Total question evaluations: 21 × 200 = 4,200
```

Runs execute concurrently via the Runner Pool (configurable pool size).

---

## 6. Phase C: Judge & Score

### Per-Answer Judging

For each (question, answer) pair:

```
System: You are a PRISM evaluation judge. Score this answer against
the provided rubric.

Question: {question_text}
Expected Answer: {expected_answer}
Actual Answer: {raw_answer}
Retrieved Context: {retrieval_context}
Rubric: {rubric}

Score 0.0 to 1.0 based on the rubric.
Also score each CL dimension that this question tests.

Respond in JSON:
{
  "score": 0.X,
  "explanation": "...",
  "cl_dimensions": {
    "stability": 0.X,
    "knowledge_update": 0.X
  }
}
```

### Aggregation

For each CL dimension d:
```
score(d) = mean(
  judge_score(q) × cl_weight(q, d)
  for q in questions where d in q.cl_categories
)
```

Weighted total:
```
prism_score = Σ(score(d) × weight(d)) for d in dimensions
```

### Confidence Intervals

Bootstrap 95% confidence intervals by resampling questions with
replacement (1000 iterations). Report:
- Point estimate
- 95% CI lower bound
- 95% CI upper bound

Systems within overlapping CIs should be reported as "not significantly
different."

---

## 7. The Meta-Loop (CL-on-CL)

### Gap Analysis (after each cycle)

1. **Under-tested dimensions**: Which dimensions had < 80% of target
   question count?
2. **Saturated questions**: Which questions scored > 0.95 across ALL
   systems? → Candidates for retirement.
3. **Too-hard questions**: Which questions scored < 0.05 across ALL
   systems? → Candidates for difficulty adjustment.
4. **Low-variance dimensions**: Which dimensions showed < 0.1 standard
   deviation across systems? → Not discriminating, need harder questions.
5. **Judge disagreement**: Which questions had > 0.3 variance across
   multiple judge runs? → Ambiguous rubric, needs refinement.

### Cycle Advancement

When advancing from cycle N to cycle N+1:

1. Retire saturated questions (replace with harder ones on same dimensions)
2. Adjust difficulty of too-hard questions (split into sub-questions)
3. Generate additional questions for under-tested dimensions
4. Refine rubrics for high-disagreement questions
5. Update CL category specs if gap analysis reveals structural issues

### Convergence Properties

- **Cycle 1-3**: Easy questions dominate. Retrieval quality matters most.
  Top system ~60-70%.
- **Cycle 5-10**: Easy questions retired. Advanced CL dimensions differentiate.
  Top system ~55-65%.
- **Cycle 20+**: Mostly level 3-5 difficulty. Only genuine CL machinery survives.
  Top system ~45-55%.
- **Asymptote**: Score ceiling recedes forever because difficulty level 5
  questions approach AGI-level cognition. The benchmark cannot saturate.

---

## 8. Data Model (Postgres)

```sql
-- ════════════════════════════════════════════════════════
-- Core entities
-- ════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE prism_suites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_number INTEGER NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  generator_model TEXT NOT NULL,
  judge_model TEXT,
  cl_category_weights JSONB NOT NULL,
  total_questions INTEGER NOT NULL,
  validated_questions INTEGER,
  coverage_scores JSONB,
  status TEXT DEFAULT 'draft'
    CHECK (status IN ('draft', 'validated', 'active', 'retired')),
  metadata JSONB
);

CREATE INDEX idx_suites_cycle ON prism_suites(cycle_number);
CREATE INDEX idx_suites_status ON prism_suites(status);

CREATE TABLE prism_questions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  suite_id UUID NOT NULL REFERENCES prism_suites(id) ON DELETE CASCADE,
  question_text TEXT NOT NULL,
  expected_answer TEXT NOT NULL,
  rubric JSONB NOT NULL,
  cl_categories JSONB NOT NULL,
  difficulty INTEGER NOT NULL CHECK (difficulty BETWEEN 1 AND 5),
  requires_state BOOLEAN DEFAULT false,
  ingestion_context JSONB,
  validation_score FLOAT,
  generation_metadata JSONB,
  retired_at TIMESTAMPTZ,
  retirement_reason TEXT
    CHECK (retirement_reason IN ('saturated', 'ambiguous', 'too_hard', 'duplicate', NULL)),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_questions_suite ON prism_questions(suite_id);
CREATE INDEX idx_questions_cl ON prism_questions USING gin(cl_categories);
CREATE INDEX idx_questions_difficulty ON prism_questions(difficulty);
CREATE INDEX idx_questions_active ON prism_questions(suite_id) WHERE retired_at IS NULL;

-- ════════════════════════════════════════════════════════
-- Registered memory systems
-- ════════════════════════════════════════════════════════

CREATE TABLE prism_systems (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT UNIQUE NOT NULL,
  display_name TEXT NOT NULL,
  mcp_endpoint TEXT NOT NULL,
  transport TEXT NOT NULL CHECK (transport IN ('stdio', 'sse')),
  version TEXT,
  tool_count INTEGER,
  capabilities JSONB,
  registered_at TIMESTAMPTZ DEFAULT now(),
  last_seen_at TIMESTAMPTZ
);

-- ════════════════════════════════════════════════════════
-- Execution tracking
-- ════════════════════════════════════════════════════════

CREATE TABLE prism_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  suite_id UUID NOT NULL REFERENCES prism_suites(id),
  system_id UUID NOT NULL REFERENCES prism_systems(id),
  llm_backend TEXT NOT NULL,
  judge_model TEXT NOT NULL,
  cycle_number INTEGER NOT NULL,
  started_at TIMESTAMPTZ DEFAULT now(),
  completed_at TIMESTAMPTZ,
  status TEXT DEFAULT 'pending'
    CHECK (status IN ('pending', 'running', 'judging', 'completed', 'failed', 'cancelled')),
  aggregate_scores JSONB,
  weighted_total FLOAT,
  confidence_intervals JSONB,
  error_message TEXT,
  metadata JSONB
);

CREATE INDEX idx_runs_suite ON prism_runs(suite_id);
CREATE INDEX idx_runs_system ON prism_runs(system_id);
CREATE INDEX idx_runs_cycle ON prism_runs(cycle_number);
CREATE INDEX idx_runs_status ON prism_runs(status);

CREATE TABLE prism_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id UUID NOT NULL REFERENCES prism_runs(id) ON DELETE CASCADE,
  question_id UUID NOT NULL REFERENCES prism_questions(id),
  -- Execution trace
  ingestion_ms INTEGER,
  retrieval_ms INTEGER,
  answer_ms INTEGER,
  raw_answer TEXT,
  retrieval_context TEXT,
  -- Judging
  judge_score FLOAT CHECK (judge_score BETWEEN 0 AND 1),
  judge_explanation TEXT,
  cl_dimension_scores JSONB,
  judge_raw_response JSONB,
  -- Human override
  override_score FLOAT CHECK (override_score BETWEEN 0 AND 1),
  override_reason TEXT,
  override_at TIMESTAMPTZ,
  -- Meta
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_results_run ON prism_results(run_id);
CREATE INDEX idx_results_question ON prism_results(question_id);

-- ════════════════════════════════════════════════════════
-- Leaderboard
-- ════════════════════════════════════════════════════════

CREATE TABLE prism_leaderboard (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_number INTEGER NOT NULL,
  system_id UUID NOT NULL REFERENCES prism_systems(id),
  system_name TEXT NOT NULL,
  llm_backend TEXT NOT NULL,
  -- 9 CL dimension scores (0.0 - 1.0)
  stability_score FLOAT,
  plasticity_score FLOAT,
  knowledge_update_score FLOAT,
  consolidation_score FLOAT,
  temporal_score FLOAT,
  transfer_score FLOAT,
  uncertainty_score FLOAT,
  forgetting_score FLOAT,
  feedback_score FLOAT,
  -- Aggregate
  weighted_total FLOAT,
  -- Confidence intervals (JSONB: {dim: {lower: X, upper: Y}})
  confidence_intervals JSONB,
  -- Provenance
  suite_id UUID REFERENCES prism_suites(id),
  run_id UUID REFERENCES prism_runs(id),
  computed_at TIMESTAMPTZ DEFAULT now(),
  -- Unique per cycle × system × model
  UNIQUE (cycle_number, system_id, llm_backend)
);

CREATE INDEX idx_leaderboard_cycle ON prism_leaderboard(cycle_number);
CREATE INDEX idx_leaderboard_system ON prism_leaderboard(system_id);
CREATE INDEX idx_leaderboard_total ON prism_leaderboard(weighted_total DESC);

-- ════════════════════════════════════════════════════════
-- CL Meta-Loop tracking
-- ════════════════════════════════════════════════════════

CREATE TABLE prism_cycles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_number INTEGER UNIQUE NOT NULL,
  started_at TIMESTAMPTZ DEFAULT now(),
  completed_at TIMESTAMPTZ,
  suite_id UUID REFERENCES prism_suites(id),
  -- Gap analysis from prior cycle
  prior_gap_analysis JSONB,
  -- What changed this cycle
  retired_question_count INTEGER DEFAULT 0,
  new_question_count INTEGER DEFAULT 0,
  difficulty_adjustments JSONB,
  weight_adjustments JSONB,
  -- Results summary
  participating_systems INTEGER,
  participating_models INTEGER,
  top_system TEXT,
  top_weighted_total FLOAT,
  metadata JSONB
);

CREATE TABLE prism_cycle_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  from_cycle INTEGER NOT NULL,
  to_cycle INTEGER NOT NULL,
  gap_analysis JSONB NOT NULL,
  under_tested_dims TEXT[],
  saturated_question_ids UUID[],
  too_hard_question_ids UUID[],
  low_variance_dims TEXT[],
  recommendations JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

---

## 9. MCP Tool Surface (29 tools)

### Suite Management (6)

| Tool | Description | Key Parameters |
|------|-------------|----------------|
| `generate_suite` | Phase A: LLM generates benchmark suite from CL specs | target_questions, focus_dimensions |
| `validate_suite` | Run CL coverage judge on draft suite | suite_id |
| `list_suites` | List all suites with status and coverage | status filter |
| `get_suite` | Full suite details with all questions | suite_id |
| `retire_question` | Retire a question with reason | question_id, reason |
| `import_external` | Import from BEAM/LongMemEval/etc with CL tagging | source, file_path |

### Execution (5)

| Tool | Description | Key Parameters |
|------|-------------|----------------|
| `run_eval` | Execute suite against one memory system | suite_id, system, llm_backend |
| `run_matrix` | Full evaluation matrix (N systems × M models) | suite_id, systems[], models[] |
| `get_run_status` | Check in-progress run | run_id |
| `get_run_results` | Detailed results for completed run | run_id |
| `cancel_run` | Cancel in-progress run | run_id |

### Judging (3)

| Tool | Description | Key Parameters |
|------|-------------|----------------|
| `judge_run` | Phase C: LLM judges all answers, computes CL scores | run_id |
| `judge_single` | Judge one answer (debugging) | result_id |
| `override_judgment` | Human override with audit trail | result_id, new_score, reason |

### Leaderboard (4)

| Tool | Description | Key Parameters |
|------|-------------|----------------|
| `get_leaderboard` | Current rankings, filterable | cycle, dimension, system, limit |
| `get_leaderboard_history` | Scores over time for trend analysis | system, from_cycle, to_cycle |
| `compare_systems` | Head-to-head across all 9 dimensions | system_a, system_b, cycle |
| `get_dimension_leaders` | Top system per CL dimension | cycle |

### CL Meta-Loop (5)

| Tool | Description | Key Parameters |
|------|-------------|----------------|
| `analyze_gaps` | Gap analysis on current cycle | cycle |
| `propose_refinements` | LLM proposes spec refinements from gaps | cycle |
| `advance_cycle` | Move to next cycle with harder questions | (none) |
| `get_cycle_history` | Full history of cycles and improvements | (none) |
| `detect_saturation` | Find questions all systems ace | threshold (default 0.95) |

### Configuration (6)

| Tool | Description | Key Parameters |
|------|-------------|----------------|
| `set_cl_weights` | Update 9-dim weight vector (must sum to 1.0) | weights map |
| `register_system` | Register memory system with MCP endpoint | name, mcp_endpoint, transport |
| `list_systems` | List registered systems | (none) |
| `set_judge_model` | Configure judge LLM | model |
| `set_generator_model` | Configure generator LLM | model |
| `get_config` | Current full configuration | (none) |

---

## 10. CL Category Specifications

Each category is defined by a structured spec that drives question generation
and answer judging. Full specs are in the Elixir module
`Prism.Benchmark.CLCategories`.

### Stability (weight: 0.20)

**Question templates:**
- Retention after update: Ingest 10 facts, add 10 new, query originals
- Stability under load: Ingest fact A, then 100 unrelated facts, query A
- Preference persistence: State preference P, 50 interactions later, query P

**Difficulty levels:**
1. Recall after 5 intervening facts
2. Recall after 50 intervening facts
3. Recall after 200 facts across sessions
4. Recall of nuanced reasoning chains
5. Recall under adversarial distraction (similar-but-different facts)

**External anchors:** BEAM (10M scale), TRACE (General Ability Delta)

### Plasticity (weight: 0.18)

**Question templates:**
- Immediate learning: Teach new fact, immediately query
- Rule learning: Define rule ("always respond in JSON"), test compliance
- Preference update: Change from X to Y, query in old context

**Difficulty levels:**
1. Simple fact acquisition
2. Rule/procedure acquisition
3. Preference change with conflicting prior
4. Multi-step procedure from examples
5. Implicit preference inferred from behavior

**External anchors:** MemoryBench, Evo-Memory, MemoryAgentBench (TTL)

### Knowledge Update (weight: 0.15)

**Question templates:**
- Simple contradiction: "Live in NYC" → "Moved to Austin" → "Where?"
- Cascade update: A depends on B depends on C, update C, query A
- Temporal supersession: Fact at T1, contradicted at T2, query at T3

**Difficulty levels:**
1. Explicit contradiction, same session
2. Explicit contradiction, cross-session
3. Implicit contradiction requiring inference
4. Multi-hop cascade (A→B→C, update A)
5. Semantic contradiction with no lexical overlap

**External anchors:** BEAM (contradiction resolution), LongMemEval, GraphMemBench

### Consolidation (weight: 0.12)

**Question templates:**
- Summarization: 50 sessions → "comprehensive summary"
- Pattern recognition: 20 bug reports → "most common failure pattern"
- Frequency awareness: Topic A×15, topic B×3 → "what do we discuss most?"

**Difficulty levels:**
1. Summarize 5 short sessions
2. Summarize 20 sessions, identify themes
3. Identify patterns across 50+ episodes
4. Abstract a rule from observed examples
5. Hierarchical: episodes → themes → insights → strategy

**External anchors:** BEAM (summarization), MemBench (reflective), MemoryAgentBench (LRU)

### Temporal Reasoning (weight: 0.10)

**Question templates:**
- Chronological ordering: Events at T1, T2, T3 → "What happened first?"
- Relative time: "Two weeks ago" → resolve to date
- Recency awareness: Old fact vs. recent fact, query prefers recent

**Difficulty levels:**
1. Simple before/after with explicit dates
2. Relative dates ("last week")
3. Session chronology ("which session first?")
4. Multiple timelines
5. Implicit temporal ordering from context clues

**External anchors:** LongMemEval, BEAM (event ordering + temporal)

### Cross-Domain Transfer (weight: 0.08)

**Question templates:**
- Structural transfer: Auth patterns in Project A → security in Project B
- Analogical transfer: Concept X in domain A → "What's analogous in B?"
- Procedural transfer: Workflow in context A → adapt to context B

**Difficulty levels:**
1. Same domain, different project
2. Related domains (frontend → backend)
3. Distant domains (code → business strategy)
4. Abstract structural transfer (graph topology)
5. Transfer of reasoning patterns, not facts

**External anchors:** TRACE (cross-task effects), MemoryBench (multi-domain)

### Epistemic Awareness (weight: 0.07)

**Question templates:**
- Abstention: Ask about never-ingested information
- Confidence calibration: Well-supported vs. weakly-supported facts
- Gap identification: Partial information → "What don't you know?"

**Difficulty levels:**
1. Obvious unknown
2. Plausible but unmentioned
3. Partially known (some evidence, not conclusive)
4. Conflicting evidence (should express uncertainty)
5. Meta-epistemic (identify investigation priorities)

**External anchors:** SeekBench, LongMemEval (abstention), BEAM (abstention)

### Intentional Forgetting (weight: 0.05)

**Question templates:**
- Selective forget: Ingest A, delete A, query A
- Policy pruning: 100 facts varying importance, prune, query low-importance
- GDPR erasure: Personal data → erasure request → verify complete deletion

**Difficulty levels:**
1. Delete single fact
2. Cascade delete (fact + derived knowledge)
3. Policy pruning (LRU + importance)
4. Partial forget (hide from retrieval, keep for audit)
5. GDPR Article 17 full erasure with provenance audit

**External anchors:** MemoryAgentBench (selective forgetting), GraphMemBench

### Outcome Feedback (weight: 0.05)

**Question templates:**
- Retrieval feedback: Retrieve, answer wrong, signal "unhelpful", re-query
- Ranking adjustment: 10 queries, mark source unhelpful, check ranking drop
- Positive reinforcement: Mark helpful, check similar queries surface similar

**Difficulty levels:**
1. Single negative feedback → re-retrieval
2. Accumulated feedback over 5 queries → ranking shift
3. Feedback propagation to similar queries
4. Conflicting feedback signals → resolution
5. Long-term Q-value convergence over 50+ cycles

**External anchors:** MemoryBench (feedback), Evo-Memory (cumulative curves)

---

## 11. Scoring System Design

### Score Composition

```
prism_total = Σ(dimension_score[d] × weight[d]) for d in 9 dimensions

Where:
  dimension_score[d] = mean(
    effective_score(q) × cl_weight(q, d)
    for q in questions where d in q.cl_categories
  )

  effective_score(q) = override_score(q) ?? judge_score(q)
```

### Score Properties

- **Range**: 0.0 to 1.0 (displayed as 0-100%)
- **Per-dimension range**: 0.0 to 1.0
- **Confidence intervals**: Bootstrap 95% CI reported for all scores
- **No permanent 100%**: Saturation-driven retirement ensures the benchmark
  evolves to stay ahead of system capabilities

### Why It Won't Max Out

Two mechanisms prevent permanent 100%:

1. **Saturation retirement**: Questions where all systems score > 0.95 get
   retired and replaced with harder ones. The benchmark calibrates to the
   frontier.

2. **Asymptotic difficulty**: Level 5 questions test capabilities approaching
   AGI (hierarchical consolidation, reasoning pattern transfer, meta-epistemic
   awareness). These are genuinely unsolved problems.

Expected score trajectory:
- Cycle 1-3: Top system ~60-70%
- Cycle 5-10: Top system ~55-65%
- Cycle 20+: Top system ~45-55%
- The ceiling recedes forever.

---

## 12. External Benchmark Integration

PRISM can import questions from published benchmarks, automatically tagging
them with CL categories.

### Import Format

```json
{
  "source": "beam",
  "version": "1.0",
  "questions": [
    {
      "original_id": "beam_q_042",
      "question_text": "...",
      "expected_answer": "...",
      "original_category": "contradiction_resolution",
      "original_difficulty": "medium",
      "metadata": { "token_count": 100000 }
    }
  ]
}
```

### CL Category Mapping

| Source Benchmark | Source Category | PRISM CL Dimension(s) |
|-----------------|---------------|----------------------|
| BEAM | contradiction_resolution | knowledge_update |
| BEAM | event_ordering | temporal |
| BEAM | summarization | consolidation |
| BEAM | preference_following | plasticity, stability |
| BEAM | temporal_reasoning | temporal |
| BEAM | information_extraction | stability |
| BEAM | knowledge_update | knowledge_update |
| BEAM | multi_hop_reasoning | stability, transfer |
| BEAM | instruction_following | plasticity |
| BEAM | abstention | uncertainty |
| LongMemEval | single_session_user | stability |
| LongMemEval | single_session_assistant | stability |
| LongMemEval | single_session_preference | plasticity |
| LongMemEval | multi_session | stability, transfer |
| LongMemEval | temporal_reasoning | temporal |
| LongMemEval | knowledge_update | knowledge_update |
| LongMemEval | abstention | uncertainty |
| MemoryAgentBench | accurate_retrieval | stability |
| MemoryAgentBench | test_time_learning | plasticity |
| MemoryAgentBench | long_range_understanding | consolidation |
| MemoryAgentBench | conflict_resolution | knowledge_update |
| GraphMemBench | belief_revision | knowledge_update |
| GraphMemBench | intentional_forgetting | forgetting |
| GraphMemBench | uncertainty_propagation | uncertainty |

---

## 13. Deployment (Fly.io)

### fly.toml

```toml
app = "prism-eval"
primary_region = "iad"

[build]
  dockerfile = "Dockerfile"

[env]
  MIX_ENV = "prod"
  RUNNER_POOL_SIZE = "4"
  PHX_HOST = "prism-eval.fly.dev"
  POOL_SIZE = "10"

[http_service]
  internal_port = 4000
  force_https = true
  auto_stop_machines = "stop"
  auto_start_machines = true
  min_machines_running = 1

  [http_service.concurrency]
    type = "connections"
    hard_limit = 100
    soft_limit = 80

[[vm]]
  size = "shared-cpu-2x"
  memory = "1024mb"

[mounts]
  source = "prism_data"
  destination = "/app/data"
```

### Required Secrets (Fly.io)

```bash
fly secrets set ANTHROPIC_API_KEY=sk-ant-...
fly secrets set OPENAI_API_KEY=sk-...
fly secrets set DATABASE_URL=postgres://...
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)
```

### Database Setup

```bash
fly postgres create --name prism-db --region iad
fly postgres attach prism-db --app prism-eval
fly ssh console -C "bin/prism eval Prism.Release.migrate"
```

---

## 14. Observability & Telemetry

### Telemetry Events

```
[:prism, :phase_a, :generate]   → {cycle, question_count, coverage, duration_ms}
[:prism, :phase_a, :validate]   → {suite_id, accepted, rejected, duration_ms}
[:prism, :phase_b, :execute]    → {system, model, question_id, retrieval_ms, ingestion_ms}
[:prism, :phase_b, :run]        → {run_id, system, total_questions, mean_retrieval_ms}
[:prism, :phase_c, :judge]      → {run_id, question_id, score, dimension, duration_ms}
[:prism, :phase_c, :aggregate]  → {run_id, cl_scores, weighted_total}
[:prism, :meta, :gap_analysis]  → {cycle, under_tested, saturated_count, too_hard_count}
[:prism, :meta, :advance]       → {from_cycle, to_cycle, retired_count, new_count}
[:prism, :llm, :call]           → {model, prompt_length, duration_ms, tokens_used}
[:prism, :mcp, :tool_call]      → {tool, system, duration_ms, success}
```

### Metrics Dashboard

LiveDashboard (Phoenix) for real-time monitoring:
- Active runs with progress bars
- LLM API call latency histogram
- Per-system retrieval latency
- CL dimension score trends across cycles
- Question coverage heatmap
- Saturation detection alerts

---

## 15. Known Risks & Mitigations

### Risk 1: Self-Referential Collapse

**Problem**: LLM generates questions → LLM judges answers → LLM uses
judgments to generate harder questions. Could converge on "what the LLM
thinks is hard" rather than "what's actually hard."

**Mitigations**:
- Different models for generation vs. judging (mandatory)
- External benchmark anchors (BEAM, LongMemEval) as ground truth
- Per-model variance tracking (flag if model X generates easy-for-X questions)
- Human override tool at every judgment step
- Publish all prompts and rubrics for community audit

### Risk 2: Goodhart's Law

**Problem**: Memory system developers optimize for PRISM templates specifically.

**Mitigations**:
- Self-improving loop generates novel questions each cycle
- Question templates evolve based on gap analysis
- External benchmarks provide uncontrolled baseline
- Difficulty escalation outpaces optimization

### Risk 3: LLM Judge Inconsistency

**Problem**: LLM judges may score inconsistently, especially on hard dimensions
(consolidation, transfer, feedback).

**Mitigations**:
- Report confidence intervals, not just point estimates
- Run multiple judge passes, flag high-variance questions
- Human override for disputed judgments
- Separate judge reliability metric tracked per dimension

### Risk 4: MCP Adapter Unfairness

**Problem**: Different systems expose different MCP tools. An adapter that
uses the "wrong" tools disadvantages the system.

**Mitigations**:
- Auto-discover available tools via MCP tools/list
- Adapter per system written by system maintainer (or reviewed by them)
- Publish adapter code for audit
- Allow system maintainers to submit their own adapter

---

## 16. Predicted System Scores (Cycle 1)

Based on analysis of each system's published capabilities and benchmark
results. These are PREDICTIONS, not measurements.

| System | Stab | Plast | K.Upd | Consol | Temp | Trans | Uncert | Forget | Feed | **Total** |
|--------|------|-------|-------|--------|------|-------|--------|--------|------|-----------|
| Graphonomous | 0.80 | 0.80 | 0.90 | 0.80 | 0.60 | 0.70 | 0.90 | 1.00 | 0.80 | **0.80** |
| OMEGA | 0.80 | 0.70 | 0.70 | 0.60 | 0.70 | 0.50 | 0.60 | 0.70 | 0.40 | **0.67** |
| Supermemory | 0.70 | 0.80 | 0.70 | 0.60 | 0.70 | 0.60 | 0.40 | 0.60 | 0.50 | **0.66** |
| Mastra OM | 0.70 | 0.70 | 0.60 | 0.70 | 0.80 | 0.40 | 0.40 | 0.30 | 0.30 | **0.59** |
| Zep/Graphiti | 0.70 | 0.70 | 0.70 | 0.50 | 0.80 | 0.50 | 0.30 | 0.40 | 0.30 | **0.59** |
| Mem0 | 0.60 | 0.70 | 0.60 | 0.40 | 0.40 | 0.50 | 0.30 | 0.30 | 0.30 | **0.49** |
| MemPalace | 0.70 | 0.50 | 0.50 | 0.30 | 0.50 | 0.40 | 0.20 | 0.20 | 0.10 | **0.43** |

These predictions will be validated (or invalidated) by cycle 1 results.

---

## 17. Implementation Roadmap

### Phase 1: Foundation (Week 1-2)

- [ ] Scaffold Elixir project (`mix new prism --sup`)
- [ ] Ecto schemas + migrations from SQL above
- [ ] LLM client (Anthropic + OpenAI APIs)
- [ ] Basic MCP server (stdio transport, initialize + tools/list)
- [ ] CL category specs module
- [ ] Postgres on Fly.io

### Phase 2: Phase A — Generate (Week 2-3)

- [ ] Generation prompt builder
- [ ] Question parser (JSON from LLM → Ecto struct)
- [ ] Validation pass (second LLM call)
- [ ] Coverage analysis
- [ ] Store validated suite
- [ ] `generate_suite` and `validate_suite` MCP tools

### Phase 3: Phase B — Execute (Week 3-4)

- [ ] MCP adapter behavior
- [ ] Graphonomous adapter (first target)
- [ ] Runner pool (DynamicSupervisor + Tasks)
- [ ] Result storage with full trace
- [ ] `run_eval` and `run_matrix` MCP tools

### Phase 4: Phase C — Judge (Week 4-5)

- [ ] Judge prompt builder
- [ ] Per-answer scoring
- [ ] CL dimension aggregation
- [ ] Confidence interval computation (bootstrap)
- [ ] Leaderboard computation and storage
- [ ] `judge_run` and `get_leaderboard` MCP tools

### Phase 5: Meta-Loop (Week 5-6)

- [ ] Gap analysis
- [ ] Saturation detection
- [ ] Cycle advancement
- [ ] Question retirement and replacement
- [ ] `analyze_gaps` and `advance_cycle` MCP tools

### Phase 6: External Imports (Week 6-7)

- [ ] BEAM question importer with CL tagging
- [ ] LongMemEval question importer
- [ ] MemoryAgentBench question importer
- [ ] `import_external` MCP tool

### Phase 7: Additional Adapters (Week 7-8)

- [ ] Supermemory MCP adapter
- [ ] Mem0 MCP adapter
- [ ] MemPalace MCP adapter
- [ ] Zep REST → MCP wrapper

### Phase 8: Deploy & Run Cycle 1 (Week 8-9)

- [ ] Dockerfile
- [ ] Deploy to Fly.io
- [ ] Run cycle 1 with all registered systems
- [ ] Publish results to opensentience.org/prism

---

## Appendix A: Running a Full Cycle

```elixir
# 1. Generate a new suite
{:ok, suite} = Prism.Cycle.Manager.generate_suite(%{
  target_questions: 200,
  generator_model: "claude-sonnet-4-20250514"
})

# 2. Validate CL coverage (different model)
{:ok, validated} = Prism.Cycle.Manager.validate_suite(suite.id)

# 3. Run against all registered systems
{:ok, matrix} = Prism.Cycle.Manager.run_matrix(validated.id,
  systems: ["graphonomous", "mem0", "supermemory", "mempalace"],
  models: ["claude-sonnet-4-20250514", "gpt-4o"]
)

# 4. Judge all runs
for run <- matrix.runs do
  {:ok, _} = Prism.Cycle.Manager.judge_run(run.id)
end

# 5. Compute leaderboard
{:ok, board} = Prism.Leaderboard.compute(cycle: 1)

# 6. Analyze gaps and advance
{:ok, gaps} = Prism.Cycle.Manager.analyze_gaps(1)
{:ok, _} = Prism.Cycle.Manager.advance_cycle()
# → Cycle 2 begins with harder questions on weak dimensions
```

## Appendix B: MCP Integration Example

```bash
# Add PRISM to Claude Code
claude mcp add prism -- elixir -S mix run --no-halt

# Or connect via SSE (when deployed to Fly.io)
claude mcp add prism --transport sse --url https://prism-eval.fly.dev/mcp
```

Then in Claude Code:
```
> Run PRISM cycle 1 against Graphonomous and Mem0
> Show me the PRISM leaderboard
> Compare Graphonomous vs Supermemory on all CL dimensions
> Which dimension does MemPalace score worst on?
> Advance to cycle 2
```
