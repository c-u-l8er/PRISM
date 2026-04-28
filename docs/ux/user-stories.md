# PRISM — User Stories

Canonical user-story catalog. Used for Playwright tests + Claude Design input for dashboard expansion.

**Scope:** OS-009 PRISM benchmark engine. Phoenix LiveView today (landing + API leaderboard); richer UI planned.
**Unit-test surface covered:** `test/**` (172 tests).

---

## Story 1 · Compose scenario from git repo (BYOR)

- **Persona:** ML researcher building a CL benchmark
- **Goal:** Walk a git repo's commit history, extract CL challenges, register as anchor scenarios
- **Prerequisite:** Git repo with meaningful commit diffs
- **Steps:**
  1. Call `compose(action: "byor_register", repo_url, domain)`
  2. PRISM walks history, ingests diffs, detects CL signals
  3. For each signal, generates scenario `{kind: anchor, domain, difficulty, sessions}`
  4. Validates against 9 CL dimension rubrics
  5. Scenarios stored in SQLite; ready to run
- **Success:** 5-20 anchor scenarios created; ready for benchmarking
- **Covers:** scenario composition, git diff ingestion, CL dimension detection, validation — ~30 unit tests
- **UI status:** mcp-only
- **Claude Design hook:** Scenario explorer showing commit-to-scenario mapping with CL dimension labels

## Story 2 · Run closed-loop scenario sequence against a memory system

- **Persona:** Benchmark engineer comparing Graphonomous vs baseline
- **Goal:** Run S1→S2→S3 without resetting memory; measure if system actually learns from first interaction
- **Prerequisite:** Scenario suite loaded; target system configured; MCP endpoint available
- **Steps:**
  1. Call `interact(action: "run_sequence", scenario_ids: [S1,S2,S3], system_id, llm_backend)`
  2. PRISM drives system through S1 (store trace, no reset)
  3. S2 runs on same memory state; measures if system retrieves S1's learnings
  4. S3 runs; measures improvement
  5. Transcript collected per scenario
- **Success:** Loop closure rate recorded ("system improved 15% from S1 to S3")
- **Covers:** scenario sequencing, system invocation, state preservation, trace collection — ~40 unit tests
- **UI status:** mcp-only (Phoenix web layer exists but only for leaderboard)
- **Claude Design hook:** Sequence replay timeline showing memory state at each scenario boundary

## Story 3 · Three-layer judgment (L2 dimensions + L3 meta-audit)

- **Persona:** Evaluation engineer validating CL scores
- **Goal:** Judge transcript across 9 CL dimensions; meta-judge for consistency
- **Prerequisite:** Transcript collected; 2 different LLM models (L2 and L3 MUST differ)
- **Steps:**
  1. Call `observe(action: "judge_transcript", transcript_id, judge_model)`
  2. L2: 9 parallel judges, each scoring one dimension
  3. Outputs: `{dimension, score 0-1, evidence, confidence}`
  4. Call `observe(action: "meta_judge_batch", run_id, meta_judge_model)`
  5. L3 audits L2 scores; flags outliers; suggests overrides
- **Success:** Composite score with confidence interval; meta-judge agreement ≥0.85
- **Covers:** judgment rubrics, dimension scoring, meta-judgment — ~35 unit tests
- **UI status:** mcp-only (score rendering planned)
- **Claude Design hook:** Dimension scorecard with L2/L3 comparison + confidence bars

## Story 4 · View the leaderboard (existing web UI)

- **Persona:** Anyone evaluating "which memory system is best for my task"
- **Goal:** See the ranked table of all benchmarked systems
- **Prerequisite:** At least 1 cycle of runs completed
- **Steps:**
  1. Navigate to `prism-eval.fly.dev/`
  2. Scroll to "Install" / loop / dimensions sections
  3. Fetch `/api/leaderboard` (JSON); see cycle, rows with `system, version, composite, rank, dims{}`, `loop_closure_rate`
  4. See which system ranks #1 per dimension
- **Success:** Clear picture of which system is best overall + per-dimension
- **Covers:** leaderboard query, rank computation, dim score aggregation — ~20 unit tests
- **UI status:** exists-today (landing + JSON endpoint). HTML rendering of leaderboard itself planned.
- **Claude Design hook:** Leaderboard table with dim sparklines + system comparison drilldown

## Story 5 · Reflect on failures and evolve scenarios

- **Persona:** Benchmark curator improving test quality
- **Goal:** Retire saturated scenarios; generate new ones to cover gaps
- **Prerequisite:** Diagnostics report with failure clusters + coverage gaps
- **Steps:**
  1. Call `diagnose(action: "failure_patterns", system_id, dimension)`
  2. Returns: failure clusters, root-cause candidates, under-tested dimensions
  3. Call `reflect(action: "analyze_gaps", cycle)`
  4. Reports: dims with <50% coverage, saturated scenarios (100% pass), zero-representation domains
  5. Call `reflect(action: "evolve", recommendations)`
- **Success:** Coverage improved from 60% to 85% across 9 dimensions
- **Covers:** failure clustering, gap analysis, scenario evolution — ~25 unit tests
- **UI status:** mcp-only
- **Claude Design hook:** Gap heatmap (dimension × domain coverage matrix) with saturation labels

## Story 6 · Compare two memory systems head-to-head

- **Persona:** Product manager choosing which memory to ship
- **Goal:** Head-to-head A vs B; see per-dimension winner
- **Prerequisite:** Both systems have runs in DB
- **Steps:**
  1. Call `diagnose(action: "compare_systems", system_a, system_b, cycle)`
  2. PRISM aligns runs to same scenario suite
  3. Returns: `{dimension: [a_score, b_score, winner, p_value]} × 9`
  4. Weighted leaderboard rank computed
  5. Drill into per-dimension transcripts
- **Success:** Clear recommendation ("A wins 5/9 dims; B superior on transfer")
- **Covers:** comparison logic, statistical significance, weighted scoring — ~22 unit tests
- **UI status:** mcp-only
- **Claude Design hook:** 9-axis radar chart overlaying both systems' profiles

---

**Tests to implement first:** Story 4 (leaderboard — JSON endpoint works today, needs a polished HTML renderer), Story 6 (compare — showy + useful).
