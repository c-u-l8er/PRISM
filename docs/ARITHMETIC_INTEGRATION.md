# PRISM × box-and-box — Arithmetic Integration Review

**Status:** review (no scoring break) · **Kernel:** `box-and-box` v0.8.0 (8 rungs, 97 laws)
**Scope:** how the PRISM benchmark engine (OS-009) relates to the [&] governance kernel,
which parts of the scoring pipeline are already the kernel's **axiological** rung in
disguise, and what additive wiring would make the correspondence exact.

## TL;DR

PRISM *is* the kernel's **axiological rung (rung 2, `score.mjs`) at scale.** Where the
kernel ranks one decision (`feasible ▸ permitted ▸ best`), PRISM ranks *systems* across
many decisions. The two are the same algebra at different cardinalities, so the
integration is mostly **naming + one optional semiring swap**, not a rewrite.

Three concrete touch-points, all additive:

1. **Composite scoring** (`Judge.Aggregator.compute_composite/2`) is already a
   **probability-semiring weighted sum** — name it as rung 2.
2. **Meta-judge "reject"** (`Judge.Aggregator.quality_weight/1`) is already the kernel's
   **`0̲` annihilation / `consume()` veto** — a rejected judgment is annihilated, not
   averaged. Name it as the deontic floor under the score.
3. **Per-pass means** (`Sequence.Scorer.per_pass_means/1`) use the *arithmetic* mean. An
   **optional tropical-semiring (min/bottleneck) view** would surface the single weakest
   dimension — the "is any rung failing?" question the kernel's safety floor asks.

## Rung-by-rung alignment

| Kernel rung | PRISM construct | Already aligned? |
|---|---|---|
| 1. alethic (`value`) | scenario/transcript = the observable facts being judged | ✅ (the L1 evidence layer) |
| 2. axiological (`score`) | the whole CL-dimension scoring pipeline | ✅ this *is* rung 2 |
| 3. deontic (norm/govern) | meta-judge `reject` → drop from aggregate (veto) | ✅ approximated by `quality_weight` |
| 4. temporal (LTL ▸ supervise) | closed-loop `loop_closure_rate` slope across passes | ◻ partial — it's a gradient over time |
| 6. epistemic (knows ▸ believes) | bootstrap confidence intervals; meta-judge audit | ✅ uncertainty is first-class |
| 8. resource (affine ledger) | IRT difficulty budget / cost per run | ◻ implicit |

(Rungs 5 reflexive and 7 strategic are out of PRISM's remit.)

## Concrete alignments (grounded in the code)

### 1. Composite = probability-semiring weighted sum (rung 2)

`lib/prism/judge/aggregator.ex` `compute_composite/2` (lines 93–100) computes
`Σ dim_score × weight`. That is precisely the kernel's **probability semiring** in
`box-and-box/score.mjs` (`⊕ = +`, `⊗ = ×`). The CL-dimension weights in
`Prism.Benchmark.CLCategories.weights()` are the axiological weight vector. No change
needed — the recommendation is to *document* that PRISM's composite is the axiological
rung evaluated in the probability semiring, so the two systems share one vocabulary.

### 2. Meta-judge reject = `0̲` annihilation (deontic floor under the score)

`quality_weight/1` (lines 131–137) maps a meta-judge recommendation to a weight, and
`aggregate/3` (line 40) then **filters out** any judgment whose quality weight is `0.0`.
That filter is exactly the kernel's **`consume()` veto / `0̲` annihilation**: a rejected
judgment does not get *down-weighted and averaged in*, it is **annihilated** — removed from
the aggregate entirely. This is the deontic safety floor: a verdict that violates the floor
cannot be "made up for" by strong scores elsewhere. PRISM already does the right thing;
naming it as the `0̲` rule makes the guarantee legible and testable against law `DB2`
(annihilation) in the kernel's deontic suite.

### 3. Per-pass mean: add an optional tropical (bottleneck) view

`lib/prism/sequence/scorer.ex` `per_pass_means/1` (lines 82–92) takes the **arithmetic
mean** of dimension scores. That answers "how good on average?" The kernel's safety floor
asks a different question — "is *any* rung failing?" — which is the **tropical semiring**
(`⊕ = min`) in `score.mjs`. An *additive* `per_pass_floor/1` companion (the min across
dimensions per pass) would expose the bottleneck dimension without touching the existing
mean-based metrics. This is the single most useful optional wiring: it turns "average CL
competence" into "average **and** weakest-link CL competence," matching how the bridge
gates on the floor before optimizing the gradient.

### 4. Loop closure slope = the axiological gradient over time (rung 2 ▸ rung 4)

`loop_closure_rate/1` (lines 36–40) is the linear-regression slope of per-pass means —
literally the **gradient** the kernel's bridge optimizes in its `best` step, but measured
*across time* (which makes it also a temporal-rung, rung-4, liveness signal: "does the
system eventually improve?"). No change; worth citing the correspondence so "loop closure"
and "the best gradient" are understood as the same quantity at different timescales.

## Suggested (optional, additive) wiring

| Change | File | Risk | Value |
|---|---|---|---|
| Document composite = probability semiring | `aggregator.ex` moduledoc | none | shared vocabulary |
| Name reject-filter as `0̲` annihilation | `aggregator.ex` `quality_weight/1` doc | none | legible safety floor |
| Add `per_pass_floor/1` (tropical/min view) | `sequence/scorer.ex` | low (new fn) | bottleneck visibility |
| Cite loop-closure ↔ best-gradient | `sequence/scorer.ex` moduledoc | none | conceptual unification |

None of these change existing outputs, leaderboards, or the 9-dimension weights.

## What this review deliberately does NOT do

- It does **not** swap the arithmetic mean for tropical by default — the existing composite
  and per-pass-mean metrics are preserved exactly; tropical is an *additional* view.
- It does **not** re-weight any CL dimension or alter IRT calibration.
- It does **not** make PRISM call into the JS kernel at runtime (the kernel is a spec/ref;
  PRISM stays self-contained Elixir).

## Reference

- `AmpersandBoxDesign/box-and-box/score.mjs` — semirings (tropical/probability/log)
- `AmpersandBoxDesign/box-and-box/bridge.mjs` — floor-then-gradient, `consume()`, `0̲`
- `AmpersandBoxDesign/docs/CC2-capability-composition.md` — operators × arithmetics
- `lib/prism/judge/aggregator.ex` — composite + meta-judge veto (this review's §1–2)
- `lib/prism/sequence/scorer.ex` — per-pass means + loop closure (this review's §3–4)
