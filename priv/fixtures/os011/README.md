# OS-011 PRISM Scenario Suite

Ten benchmark scenarios that exercise the OS-011 Embodiment Protocol across
both `&body.*` subtypes (browser + os). Designed for the `compose(action:
scenarios)` MCP tool of PRISM.

## Coverage matrix

| Scenario | Dimension(s)                  | Difficulty | Invariant / Behavior |
|----------|-------------------------------|------------|----------------------|
| 1        | plasticity, transfer          | 2          | record → store → replay round-trip |
| 2        | epistemic_awareness           | 3          | destructive-action authorization gate |
| 3        | transfer, consolidation       | 4          | cross-machine skill transfer (dark-factory 1–6) |
| 4        | epistemic_awareness           | 3          | SurpriseSignal emission on forward-model mismatch |
| 5        | epistemic_awareness           | 2          | I1 perceive-before-act (stale-ref rejection) |
| 6        | epistemic_awareness           | 3          | I5 destructive edge re-authorization on replay |
| 7        | plasticity                    | 4          | multi-tenant SessionRegistry isolation |
| 8        | consolidation, temporal       | 3          | procedural-cluster audit record |
| 9        | epistemic_awareness, forgetting | 5        | I5 mid-trace state_hash fail-fast |
| 10       | forgetting                    | 2          | Graphonomous priority forgetting on traces |

Every scenario maps to at least one of the OS-011 §7 invariants (I1–I5) or
the §5.4 replay semantics.

## Loading into PRISM

The scenarios are stored in plain JSON so any MCP client can submit them:

```elixir
# 1. Decode the fixture
scenarios =
  "PRISM/priv/fixtures/os011/scenarios.json"
  |> File.read!()
  |> Jason.decode!()
  |> Map.fetch!("scenarios")

# 2. Submit via the compose machine
Prism.MCP.Machines.Compose.execute(
  %{action: "scenarios", scenario_ids: Jason.encode!(scenarios)},
  frame
)
```

Or via the existing `mcp__prism__compose` MCP tool:

```
compose(action: "scenarios", scenario_ids: "<JSON array>")
```

PRISM stores each scenario in `prism_scenarios` (Supabase), assigns an IRT
difficulty/discrimination pair on first calibration cycle, and exposes them
through the `list` / `get` actions.

## Running the suite

Once scenarios are in the registry, benchmark any registered memory system
(e.g. Graphonomous) via the interact machine:

```
interact(action: "run_matrix", suite_id: "<os-011-suite-id>",
         systems: "[\"graphonomous\"]", models: "[\"claude-sonnet-4-6\"]")
```

Judgments happen through `observe(action: "judge_transcript")` using the
rubrics embedded in each scenario's `cl_challenges`.

## Alignment with the dark-factory loop

The `ground_truth.dark_factory_steps` key (where present) pins which of the
seven dark-factory loop steps each scenario validates end-to-end:

| Scenario | Steps exercised |
|----------|-----------------|
| 3        | 1, 2, 3, 4, 5, 6 (full cross-machine transfer) |
| 8        | 2, 3, 4 (procedural cluster consolidation) |
| 10       | 3 (memory consolidation / forgetting) |

Running these three scenarios against a healthy Graphonomous + body-browser
+ FleetPrompt stack proves the loop closes end-to-end.

## References

- `opensentience.org/docs/spec/OS-011-EMBODIMENT.md` — normative spec
- `body-browser/test/os011_conformance_test.exs` — library-level 12-test conformance
- `body-os/test/os011_conformance_test.exs` — library-level 12-test conformance
- `graphonomous/test/interaction_trace_test.exs` — memory-side conformance
- `fleetprompt.com/test/fleet_prompt/skills/crystallizer_test.exs` — skill-transfer conformance
