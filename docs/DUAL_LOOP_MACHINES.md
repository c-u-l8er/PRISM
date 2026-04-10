# Dual- and Triple-Loop Machine Architecture

> **PULSE update (OS-010, 2026-04):** With the introduction of OS-010 PULSE,
> the loop-interlock pattern documented here is now formalized as a manifest
> standard. Graphonomous, PRISM, AgenTroMatic, and every other portfolio loop
> declare their phases in `<loop>.pulse.json` files (see `/PULSE/manifests/`),
> validated against `pulse-loop-manifest.v0.1.json`. The "dual loop" is a
> special case of arbitrarily nestable PULSE loops — the same machine grouping
> works at any depth, and PRISM's `interact` phase reads the inner system's
> PULSE manifest to discover the `retrieve` boundary at runtime rather than
> hard-coding the integration. See "Triple loop and beyond" below.

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

## Triple loop and beyond — PULSE generalization

The Graphonomous ↔ PRISM dual loop is the canonical example, but the [&]
ecosystem actually runs **at least three** nested loops today:

```
PRISM (outer)        compose → interact → observe → reflect → diagnose
  │
  └─ Graphonomous    retrieve → route → act → learn → consolidate
       │
       └─ Deliberation    survey → triage → dispatch → act → learn
```

OS-010 PULSE encodes this nesting in each manifest's `nesting` block:

- `prism.benchmark` declares `inner_loops: [graphonomous.continual_learning]`
- `graphonomous.continual_learning` declares `inner_loops: [graphonomous.deliberate]` and `parent_loop: prism.benchmark`
- `graphonomous.deliberate` declares `parent_loop: graphonomous.continual_learning`

PULSE supports unbounded nesting depth. OS-008 (Agent Harness, draft) is
expected to add a fourth outer layer that wraps PRISM itself — when it
ships, the only change required is a new manifest with
`inner_loops: [prism.benchmark]`. No code changes to existing machines.

### Why this matters for the machine architecture

The 5/6/11-tool count documented above is a **floor**, not a ceiling.
Adding a third loop adds at most 5 more machines (one per phase kind), and
because PULSE manifests declare the inner-loop boundary explicitly, the
outer machines do not need to learn about inner machines individually.
PRISM's `interact` machine, for example, drives any PULSE-conforming
inner loop through its declared `retrieve` phase — it does not need a
Graphonomous-specific code path.

| Layers in session | Tool count (machines) | Tool count (legacy v1) |
|---|---|---|
| Graphonomous alone | 5 | 29 |
| Graphonomous + PRISM | 11 | 76 |
| Graphonomous + PRISM + OS-008 Harness | ~16 | ~100+ |
| Graphonomous + PRISM + OS-008 + AgenTroMatic deliberation | ~21 | ~130+ |

The savings compound with depth, and PULSE's manifest standard is what
makes the composition algebraic instead of ad-hoc.

### Three-protocol stack at runtime

```
┌──────────────────────────────────────────────────────────┐
│  PRISM    — measures loops over time      (diagnostic)   │ OS-009
├──────────────────────────────────────────────────────────┤
│  PULSE    — declares loops + circulation   (temporal)    │ OS-010
├──────────────────────────────────────────────────────────┤
│  [&]      — composes capabilities          (structural)  │ AmpersandBoxDesign
└──────────────────────────────────────────────────────────┘
```

A loop is **PULSE-conforming** if its manifest validates against
`pulse-loop-manifest.v0.1.json` and its runtime passes all 12 conformance
tests. A system is **PRISM-evaluable** automatically once it is
PULSE-conforming — PRISM's `compose` phase reads the manifest, injects
scenarios at the declared `retrieve` boundary, and observes outcomes via
the declared `learn` phase. No bespoke per-system integration required.
