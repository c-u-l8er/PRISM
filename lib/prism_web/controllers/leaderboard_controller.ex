defmodule PrismWeb.LeaderboardController do
  use PrismWeb, :controller

  @moduledoc """
  Public leaderboard endpoint.

  This is currently a hardcoded fixture. The real wiring lands once the
  diagnose machine exposes a stable aggregate query — see
  `Prism.Leaderboard` for the query path this will call.
  """

  def index(conn, _params) do
    json(conn, %{
      cycle: 6,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      note: "Stub data — real leaderboard is wired from Prism.Diagnose in a follow-up.",
      dimensions: [
        "stability",
        "plasticity",
        "knowledge_update",
        "temporal_reasoning",
        "consolidation",
        "epistemic_awareness",
        "cross_domain_transfer",
        "intentional_forgetting",
        "outcome_feedback"
      ],
      rows: [
        %{
          rank: 1,
          system: "graphonomous",
          version: "0.4.0",
          composite: 0.782,
          loop_closure_rate: 0.91,
          dims: %{
            stability: 0.81,
            plasticity: 0.74,
            knowledge_update: 0.79,
            temporal_reasoning: 0.68,
            consolidation: 0.83,
            epistemic_awareness: 0.77,
            cross_domain_transfer: 0.72,
            intentional_forgetting: 0.88,
            outcome_feedback: 0.84
          }
        },
        %{
          rank: 2,
          system: "baseline-kv",
          version: "synthetic",
          composite: 0.431,
          loop_closure_rate: 0.22,
          dims: %{
            stability: 0.58,
            plasticity: 0.51,
            knowledge_update: 0.34,
            temporal_reasoning: 0.29,
            consolidation: 0.19,
            epistemic_awareness: 0.12,
            cross_domain_transfer: 0.22,
            intentional_forgetting: 0.44,
            outcome_feedback: 0.08
          }
        }
      ]
    })
  end
end
