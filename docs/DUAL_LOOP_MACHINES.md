# Dual-Loop Machine Architecture

## Overview

PRISM and Graphonomous are both closed-loop systems. When PRISM evaluates Graphonomous,
their loops interlock — the outer loop (PRISM) improves the benchmark while the inner
loop (Graphonomous) improves the memory. Each makes the other sharper.

The machine architecture solves the tool explosion problem: 47 PRISM tools + 29
Graphonomous tools = 76 tools in a shared session. Research shows tool selection
accuracy degrades to ~49% at that scale, and schema overhead burns 40-80K tokens.

**Solution:** Group tools by loop phase, not category. 6 PRISM machines + 5
Graphonomous machines = 11 tools. Selection accuracy jumps to ~95%.

## The Interlocking Loops

```
Graphonomous (memory loop)          PRISM (evaluation loop)
──────────────────────────          ───────────────────────
retrieve  "What do I know?"         compose    "What should I test?"
route     "What should I do?"       interact   "Run the test"
act       "Do it"                   observe    "Judge the result"
learn     "Did it work?"            reflect    "What should change?"
consolidate "Clean up"              diagnose   "What's actionable?"
```

When PRISM benchmarks Graphonomous:

```
PRISM compose ──→ PRISM interact ──→ PRISM observe ──→ PRISM reflect ──→ PRISM diagnose
                       │
                       ▼
              ┌─── Graphonomous ───┐
              │  retrieve → route  │
              │  → act → learn     │
              │  → consolidate     │
              └────────────────────┘
```

PRISM's `interact` phase drives the system-under-test through its own closed loop.
PRISM's `observe` phase judges how well that inner loop performed.
PRISM's `reflect` phase evolves scenarios based on where the inner loop failed.

## PRISM: 47 tools → 6 machines

### `compose` — "What should I test?" (9 actions)

`scenarios`, `validate`, `list`, `get`, `retire`, `import`, `byor_register`, `byor_discover`, `byor_generate`

### `interact` — "Run the test" (8 actions)

`run`, `run_sequence`, `run_matrix`, `status`, `transcript`, `cancel`, `byor_evaluate`, `byor_compare`

### `observe` — "Judge the result" (5 actions)

`judge_transcript`, `judge_dimension`, `meta_judge`, `meta_judge_batch`, `override`

### `reflect` — "What should change?" (7 actions)

`analyze_gaps`, `evolve`, `advance_cycle`, `calibrate_irt`, `cycle_history`, `byor_recommend`, `byor_infer_profile`

### `diagnose` — "What's actionable?" (13 actions)

`report`, `failure_patterns`, `retest`, `verify`, `regressions`, `suggest_fixes`, `leaderboard`, `leaderboard_history`, `compare_systems`, `dimension_leaders`, `fit_recommendation`, `compare_fit`, `task_profiles`

### `config` — Admin/setup (5 actions)

`set_weights`, `register_system`, `list_systems`, `get_config`, `create_profile`

## Graphonomous: 29 tools → 5 machines

### `retrieve` — "What do I know?" (6 actions)

`context`, `episodic`, `procedural`, `coverage`, `trace_evidence`, `frontier`

### `route` — "What should I do?" (5 actions)

`topology`, `deliberate`, `attention_survey`, `attention_cycle`, `review_goal`

### `act` — "Do it" (9 actions)

`store_node`, `store_edge`, `delete_node`, `manage_edge`, `manage_goal`, `belief_revise`, `forget_node`, `forget_policy`, `gdpr_erase`

### `learn` — "Did it work?" (5 actions)

`from_outcome`, `from_feedback`, `detect_novelty`, `from_interaction`, `contradictions`

### `consolidate` — "Clean up" (4 actions)

`run`, `stats`, `query`, `traverse`

## Combined Impact

| Scenario | Before | After |
|----------|--------|-------|
| Graphonomous alone | 29 tools | 5 tools |
| PRISM alone | 47 tools | 6 tools |
| Both in same session | 76 tools | 11 tools |

Context savings: ~85% reduction in tool schema tokens.
Selection accuracy: from ~49% (76 tools) to ~95% (11 tools).

## Implementation

Both systems use the same Elixir pattern: a single Anubis.Server.Component module
per machine with an `action` field that dispatches internally to the existing tool
implementations. The v1 tool modules are preserved as the implementation layer.

See:
- `graphonomous/lib/graphonomous/mcp/machines/` — Graphonomous machine modules
- `PRISM/lib/prism/mcp/machines/` — PRISM machine modules
- `AmpersandBoxDesign/prompts/DUAL_LOOP_MACHINES.md` — canonical architecture design
