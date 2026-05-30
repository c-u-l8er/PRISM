// prism-gallery.js — portable [&] "by domain" showcase for PRISM.
// Sources live here as plain strings (HEEx uses {} interpolation, so raw
// Elixir cannot be embedded in the .heex template). The highlighter and the
// tab switcher are scoped to #prism-industries so they never touch the rest
// of the page.
//
// The vignettes below use a fictional `PRISM.Runner` behaviour — an
// *illustrative reference host*, not a published library. The real
// conformance surface is the BYOR (bring-your-own-runner) MCP contract and
// the nine CL dimensions; any MCP-capable agent can be scored regardless of
// language.

(function () {
  var SOURCES = [
    {
      fn: "regression_runner.ex",
      lang: "Elixir / PRISM.Runner",
      src:
"defmodule Eval.RegressionRunner do\n" +
"  @moduledoc \"Nightly regression: did this week's memory build forget last week's facts?\"\n" +
"  use PRISM.Runner, system: \"acme-memory\", cycle: \"nightly\"\n" +
"\n" +
"  # 1 · COMPOSE — pull a scenario suite tagged for the dimensions we care about\n" +
"  compose :suite do\n" +
"    scenarios tag: [:retention, :forgetting, :update_consistency]\n" +
"    coverage min: 0.85, fail_below: true\n" +
"  end\n" +
"\n" +
"  # 2 · INTERACT — drive our system under test over MCP, capture the transcript\n" +
"  interact :run, via: :mcp do\n" +
"    target \"http://localhost:4010/mcp\"\n" +
"    record :transcript, grounded_in: :git_diff\n" +
"  end\n" +
"\n" +
"  # 3 · OBSERVE — three-layer judging, every score cites a transcript span\n" +
"  observe :judge do\n" +
"    dimensions [:retention, :forgetting, :update_consistency]\n" +
"    judges l1: :heuristic, l2: \"claude-opus-4-6\", l3: \"gpt-5.3-codex\"\n" +
"    on_disagreement :flag_for_human\n" +
"  end\n" +
"\n" +
"  # 4 · REFLECT — IRT recalibration; regressions page the on-call channel\n" +
"  reflect :calibrate do\n" +
"    recalibrate :irt, against: :cycle_history\n" +
"    alert when: \"delta < -0.05\", to: \"slack://#eval-regressions\"\n" +
"  end\n" +
"end\n"
    },
    {
      fn: "agent_runner.ex",
      lang: "Elixir / PRISM.Runner",
      src:
"defmodule Platform.AgentRunner do\n" +
"  @moduledoc \"Rank every agent build in the marketplace on a level playing field.\"\n" +
"  use PRISM.Runner, system: {:dynamic, :agent_id}, cycle: \"per-release\"\n" +
"\n" +
"  compose :suite do\n" +
"    import_from :beam, suite: \"longmemeval\"\n" +
"    scenarios tag: [:multi_session, :tool_recall, :instruction_following]\n" +
"  end\n" +
"\n" +
"  interact :run, via: :mcp do\n" +
"    target {:registry, \"agents.#{:agent_id}.endpoint\"}\n" +
"    budget tokens: 200_000, wall_ms: 120_000\n" +
"    record :transcript, grounded_in: :scenario_oracle\n" +
"  end\n" +
"\n" +
"  observe :judge do\n" +
"    dimensions PRISM.dimensions()      # all nine CL dimensions\n" +
"    judges l1: :heuristic, l2: \"claude-opus-4-6\"\n" +
"    publish :leaderboard, scope: :public\n" +
"  end\n" +
"\n" +
"  reflect :evolve do\n" +
"    analyze_gaps and: :evolve_scenarios   # the suite gets harder as agents improve\n" +
"    next_cycle when: \"top_score > 0.9\"\n" +
"  end\n" +
"end\n"
    },
    {
      fn: "recall_runner.ex",
      lang: "Elixir / PRISM.Runner",
      src:
"defmodule Rag.RecallRunner do\n" +
"  @moduledoc \"Prove the retrieval layer recalls the right span — and abstains when it shouldn't guess.\"\n" +
"  use PRISM.Runner, system: \"vectorvault\", cycle: \"per-index-build\"\n" +
"\n" +
"  compose :suite do\n" +
"    scenarios tag: [:retrieval_precision, :abstention, :contradiction]\n" +
"    adversarial :distractor_injection, rate: 0.3\n" +
"  end\n" +
"\n" +
"  interact :run, via: :http do\n" +
"    target \"https://api.vectorvault.dev/query\"\n" +
"    record :transcript, grounded_in: :labeled_corpus\n" +
"  end\n" +
"\n" +
"  observe :judge do\n" +
"    dimensions [:retrieval_precision, :abstention, :contradiction]\n" +
"    judges l1: :exact_match, l2: \"claude-opus-4-6\", l3: \"gpt-5.3-codex\"\n" +
"    on_disagreement :flag_for_human\n" +
"  end\n" +
"\n" +
"  reflect :report do\n" +
"    diagnose :failure_patterns\n" +
"    suggest_fixes for: :lowest_dimension\n" +
"  end\n" +
"end\n"
    },
    {
      fn: "spatial_runner.ex",
      lang: "Elixir / PRISM.Runner",
      src:
"defmodule Robotics.SpatialRunner do\n" +
"  @moduledoc \"Does the robot's memory survive a re-map? Score spatial recall across episodes.\"\n" +
"  use PRISM.Runner, system: \"warehouse-bot\", cycle: \"per-deploy\"\n" +
"\n" +
"  compose :suite do\n" +
"    scenarios tag: [:spatial_recall, :map_drift, :catastrophic_forgetting]\n" +
"    substrate :graphonomous, region: :graph_subgraph   # SCOPE-backed spatial claims\n" +
"  end\n" +
"\n" +
"  interact :run, via: :mcp do\n" +
"    target \"ros2://warehouse-bot/memory\"\n" +
"    record :transcript, grounded_in: :ground_truth_map\n" +
"  end\n" +
"\n" +
"  observe :judge do\n" +
"    dimensions [:spatial_recall, :transfer, :catastrophic_forgetting]\n" +
"    judges l1: :iou_overlap, l2: \"claude-opus-4-6\"\n" +
"  end\n" +
"\n" +
"  reflect :calibrate do\n" +
"    recalibrate :irt, against: :cycle_history\n" +
"    alert when: \"forgetting > 0.2\", to: \"pagerduty://robotics\"\n" +
"  end\n" +
"end\n"
    },
    {
      fn: "ablation_runner.ex",
      lang: "Elixir / PRISM.Runner",
      src:
"defmodule Lab.AblationRunner do\n" +
"  @moduledoc \"Reproducible ablations: hold the suite fixed, vary the architecture, compare.\"\n" +
"  use PRISM.Runner, system: {:matrix, :variant}, cycle: \"paper-2026\"\n" +
"\n" +
"  compose :suite do\n" +
"    scenarios frozen: \"sha256:9f2c…\"     # pinned for reproducibility\n" +
"    coverage min: 0.95, fail_below: true\n" +
"  end\n" +
"\n" +
"  interact :run, via: :mcp do\n" +
"    target {:matrix, [\"baseline\", \"no_consolidate\", \"no_kappa\", \"full\"]}\n" +
"    record :transcript, grounded_in: :scenario_oracle, seed: 1337\n" +
"  end\n" +
"\n" +
"  observe :judge do\n" +
"    dimensions PRISM.dimensions()\n" +
"    judges l1: :heuristic, l2: \"claude-opus-4-6\", l3: \"gpt-5.3-codex\"\n" +
"    meta_judge :audit_l2\n" +
"  end\n" +
"\n" +
"  reflect :compare do\n" +
"    compare_systems by: :dimension\n" +
"    export :leaderboard, format: :csv, to: \"./paper/tables/\"\n" +
"  end\n" +
"end\n"
    }
  ];

  var TOK = /(#[^\n]*)|("(?:[^"\\]|\\.)*")|(:[a-zA-Z_]\w*[?!]?)|(@[a-zA-Z_]\w*)|\b(defmodule|defmacro|defstruct|defp|def|do|end|fn|cond|case|if|else|quote|unquote|use|import|alias|when|true|false|nil|receive|after|with|for)\b|\b([A-Z]\w*)\b/g;

  function esc(t) {
    return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  function hl(src) {
    var out = "", last = 0, m;
    TOK.lastIndex = 0;
    while ((m = TOK.exec(src))) {
      out += esc(src.slice(last, m.index));
      var cls = m[1] ? "c" : m[2] ? "s" : m[3] ? "at" : m[4] ? "attr" : m[5] ? "kw" : "mod";
      out += '<span class="bb-' + cls + '">' + esc(m[0]) + "</span>";
      last = m.index + m[0].length;
    }
    out += esc(src.slice(last));
    return out;
  }

  function init() {
    var panels = document.querySelectorAll("#prism-industries .bb-panel");
    if (!panels.length) return;

    panels.forEach(function (panel, i) {
      var code = panel.querySelector(".bb-code");
      if (code && SOURCES[i]) code.innerHTML = hl(SOURCES[i].src);
    });

    var tabs = document.querySelectorAll("#prism-industries .bb-tab");
    tabs.forEach(function (tab, i) {
      tab.addEventListener("click", function () {
        tabs.forEach(function (t) { t.classList.remove("active"); });
        panels.forEach(function (p) { p.classList.remove("active"); });
        tab.classList.add("active");
        panels[i].classList.add("active");
      });
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
