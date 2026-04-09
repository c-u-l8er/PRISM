defmodule Prism.MCP.Machines.Observe do
  @moduledoc """
  Loop Phase 3: OBSERVE — "Judge the result"

  Unified judging machine for the PRISM evaluation loop.
  The agent calls this to evaluate interaction transcripts.

  Actions:
  - `judge_transcript`  — L2: all 9 dimensions for one transcript
  - `judge_dimension`   — L2: one specific dimension (debug)
  - `meta_judge`        — L3: meta-judge one L2 judgment
  - `meta_judge_batch`  — L3: meta-judge all L2 judgments for a run
  - `override`          — Human override with audit trail

  Replaces: judge_transcript, judge_dimension, meta_judge,
            meta_judge_batch, override_judgment
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  @valid_actions ~w(judge_transcript judge_dimension meta_judge meta_judge_batch override)

  schema do
    field(:action, :string,
      required: true,
      description:
        "Judging action: judge_transcript | judge_dimension | meta_judge | meta_judge_batch | override"
    )

    field(:transcript_id, :string, description: "Transcript UUID (judge_transcript, judge_dimension)")
    field(:judge_model, :string, description: "LLM model for judging (judge_transcript, judge_dimension)")
    field(:dimension, :string, description: "CL dimension to judge (judge_dimension)")
    field(:judgment_id, :string, description: "Judgment UUID (meta_judge, override)")

    field(:meta_judge_model, :string,
      description: "LLM model for meta-judging, MUST differ from L2 judge (meta_judge, meta_judge_batch)"
    )

    field(:run_id, :string, description: "Run UUID (meta_judge_batch)")
    field(:new_score, :number, description: "Override score 0.0-1.0 (override)")
    field(:reason, :string,
      description:
        "For override: audit reason. For judge_transcript: JSON array of agent-provided judgments, each with: dimension, challenge_composite, unprompted_score, composite_score, evidence"
    )
  end

  @impl true
  def execute(params, frame) do
    action = params |> p(:action) |> normalize_action()

    if action in @valid_actions do
      dispatch(action, params, frame)
    else
      {:reply,
       error_response(
         "Invalid action '#{inspect(p(params, :action))}'. Must be one of: #{Enum.join(@valid_actions, ", ")}"
       ), frame}
    end
  end

  defp dispatch("judge_transcript", params, frame) do
    tid = p(params, :transcript_id)
    judge_model = p(params, :judge_model) || "agent"
    judgments_json = p(params, :reason)

    with tid when not is_nil(tid) <- tid,
         judgments_json when not is_nil(judgments_json) <- judgments_json,
         {:ok, judgments_list} <- Jason.decode(judgments_json),
         transcript when not is_nil(transcript) <- Prism.Repo.get(Prism.Transcript, tid) do
      rubric_version = "prism-v3.0-cycle1"

      results =
        Enum.map(judgments_list, fn j ->
          attrs = %{
            transcript_id: transcript.id,
            dimension: j["dimension"],
            judge_model: judge_model,
            challenge_scores: j["challenge_scores"] || [],
            challenge_composite: j["challenge_composite"] || 0.0,
            unprompted_score: j["unprompted_score"] || 0.0,
            unprompted_evidence: j["unprompted_evidence"],
            composite_score: j["composite_score"] || 0.0,
            rubric_version: rubric_version,
            raw_response: j
          }

          case Prism.Repo.insert(Prism.Judgment.changeset(%Prism.Judgment{}, attrs)) do
            {:ok, judgment} -> %{id: judgment.id, dimension: judgment.dimension, score: judgment.composite_score, status: "ok"}
            {:error, changeset} -> %{dimension: j["dimension"], status: "error", error: inspect(changeset.errors)}
          end
        end)

      {:reply, success_response(%{transcript_id: tid, judgments: results}), frame}
    else
      nil ->
        {:reply, error_response("transcript_id and judgments (JSON array) required"), frame}

      {:error, reason} ->
        {:reply, error_response("Invalid judgments JSON: #{inspect(reason)}"), frame}
    end
  end

  defp dispatch("judge_dimension", params, frame) do
    tid = p(params, :transcript_id)
    dimension = p(params, :dimension)
    judge_model = p(params, :judge_model) || "agent"
    reason_json = p(params, :reason)

    with tid when not is_nil(tid) <- tid,
         dimension when not is_nil(dimension) <- dimension,
         true <- dimension in Prism.Judgment.valid_dimensions(),
         transcript when not is_nil(transcript) <- Prism.Repo.get(Prism.Transcript, tid) do
      # Parse agent-provided judgment from reason JSON
      j_data = parse_dimension_json(reason_json)

      attrs = %{
        transcript_id: transcript.id,
        dimension: dimension,
        judge_model: judge_model,
        challenge_scores: j_data.challenge_scores,
        challenge_composite: j_data.challenge_composite,
        unprompted_score: j_data.unprompted_score,
        unprompted_evidence: j_data.unprompted_evidence,
        composite_score: j_data.composite_score,
        rubric_version: "prism-v3.0-cycle1",
        raw_response: j_data.raw
      }

      case Prism.Repo.insert(Prism.Judgment.changeset(%Prism.Judgment{}, attrs)) do
        {:ok, judgment} ->
          {:reply,
           success_response(%{
             id: judgment.id,
             dimension: dimension,
             composite_score: judgment.composite_score
           }), frame}

        {:error, changeset} ->
          {:reply, error_response("Failed to insert judgment: #{inspect(changeset.errors)}"), frame}
      end
    else
      nil ->
        {:reply, error_response("transcript_id and dimension required (transcript must exist)"), frame}

      false ->
        {:reply,
         error_response(
           "Invalid dimension '#{dimension}'. Must be one of: #{Enum.join(Prism.Judgment.valid_dimensions(), ", ")}"
         ), frame}
    end
  end

  defp dispatch("meta_judge", params, frame) do
    jid = p(params, :judgment_id)
    meta_model = p(params, :meta_judge_model)
    reason_json = p(params, :reason)

    with jid when not is_nil(jid) <- jid,
         meta_model when not is_nil(meta_model) <- meta_model,
         judgment when not is_nil(judgment) <- Prism.Repo.get(Prism.Judgment, jid),
         false <- Prism.MetaJudgment.same_model_family?(judgment.judge_model, meta_model) do
      # Parse agent-provided meta-judgment scores from reason JSON, or use defaults
      meta_data = parse_meta_json(reason_json)

      composite =
        Prism.MetaJudgment.compute_composite(
          meta_data.consistency,
          meta_data.grounding,
          meta_data.compliance
        )

      recommendation = Prism.MetaJudgment.recommendation_from_score(composite)

      attrs = %{
        judgment_id: judgment.id,
        meta_judge_model: meta_model,
        consistency_score: meta_data.consistency,
        evidence_grounding_score: meta_data.grounding,
        rubric_compliance_score: meta_data.compliance,
        composite_score: composite,
        recommendation: recommendation,
        reasoning: meta_data.reasoning,
        raw_response: meta_data.raw
      }

      case Prism.Repo.insert(Prism.MetaJudgment.changeset(%Prism.MetaJudgment{}, attrs)) do
        {:ok, meta} ->
          {:reply,
           success_response(%{
             id: meta.id,
             judgment_id: jid,
             composite_score: composite,
             recommendation: recommendation
           }), frame}

        {:error, changeset} ->
          {:reply, error_response("Failed to insert meta-judgment: #{inspect(changeset.errors)}"), frame}
      end
    else
      nil ->
        {:reply, error_response("judgment_id and meta_judge_model required (judgment must exist)"), frame}

      true ->
        {:reply, error_response("meta_judge_model must be from a different model family than the L2 judge"), frame}
    end
  end

  defp dispatch("meta_judge_batch", params, frame) do
    run_id = p(params, :run_id)
    meta_model = p(params, :meta_judge_model)

    with run_id when not is_nil(run_id) <- run_id,
         meta_model when not is_nil(meta_model) <- meta_model do
      import Ecto.Query

      judgments =
        from(j in Prism.Judgment,
          join: t in Prism.Transcript,
          on: t.id == j.transcript_id,
          where: t.run_id == ^run_id,
          select: j
        )
        |> Prism.Repo.all()

      results =
        Enum.map(judgments, fn judgment ->
          if Prism.MetaJudgment.same_model_family?(judgment.judge_model, meta_model) do
            %{judgment_id: judgment.id, status: "skipped", reason: "same model family"}
          else
            # Use default scores — the agent should provide real scores via individual meta_judge calls
            composite = Prism.MetaJudgment.compute_composite(0.5, 0.5, 0.5)
            recommendation = Prism.MetaJudgment.recommendation_from_score(composite)

            attrs = %{
              judgment_id: judgment.id,
              meta_judge_model: meta_model,
              consistency_score: 0.5,
              evidence_grounding_score: 0.5,
              rubric_compliance_score: 0.5,
              composite_score: composite,
              recommendation: recommendation,
              reasoning: "Batch meta-judgment — agent should override with real scores"
            }

            case Prism.Repo.insert(Prism.MetaJudgment.changeset(%Prism.MetaJudgment{}, attrs)) do
              {:ok, meta} ->
                %{judgment_id: judgment.id, meta_id: meta.id, status: "ok", recommendation: recommendation}

              {:error, changeset} ->
                %{judgment_id: judgment.id, status: "error", error: inspect(changeset.errors)}
            end
          end
        end)

      {:reply,
       success_response(%{
         run_id: run_id,
         total: length(judgments),
         processed: length(results),
         results: results
       }), frame}
    else
      nil -> {:reply, error_response("run_id and meta_judge_model required"), frame}
    end
  end

  defp dispatch("override", params, frame) do
    jid = p(params, :judgment_id)
    new_score = p(params, :new_score)
    reason = p(params, :reason)

    with jid when not is_nil(jid) <- jid,
         new_score when is_number(new_score) <- new_score,
         reason when not is_nil(reason) <- reason,
         judgment when not is_nil(judgment) <- Prism.Repo.get(Prism.Judgment, jid) do
      # Store the override as a meta-judgment with "override" recommendation
      attrs = %{
        judgment_id: judgment.id,
        meta_judge_model: "human_override",
        consistency_score: 1.0,
        evidence_grounding_score: 1.0,
        rubric_compliance_score: 1.0,
        composite_score: new_score,
        recommendation: "accept",
        reasoning: "Human override: #{reason}",
        raw_response: %{
          "type" => "override",
          "original_score" => judgment.composite_score,
          "new_score" => new_score,
          "reason" => reason
        }
      }

      case Prism.Repo.insert(Prism.MetaJudgment.changeset(%Prism.MetaJudgment{}, attrs)) do
        {:ok, meta} ->
          # Update the judgment's composite score
          changeset =
            judgment
            |> Ecto.Changeset.change(%{composite_score: new_score / 1})

          case Prism.Repo.update(changeset) do
            {:ok, updated} ->
              {:reply,
               success_response(%{
                 judgment_id: jid,
                 original_score: judgment.composite_score,
                 new_score: updated.composite_score,
                 override_id: meta.id,
                 reason: reason
               }), frame}

            {:error, cs} ->
              {:reply, error_response("Override recorded but score update failed: #{inspect(cs.errors)}"), frame}
          end

        {:error, changeset} ->
          {:reply, error_response("Failed to record override: #{inspect(changeset.errors)}"), frame}
      end
    else
      nil -> {:reply, error_response("judgment_id, new_score, and reason required (judgment must exist)"), frame}
      _ -> {:reply, error_response("new_score must be a number"), frame}
    end
  end

  # -- Helpers --

  defp normalize_action(nil), do: nil
  defp normalize_action(v) when is_binary(v), do: v |> String.trim() |> String.downcase()
  defp normalize_action(v) when is_atom(v), do: Atom.to_string(v)
  defp normalize_action(_), do: nil

  defp success_response(result) do
    Response.tool()
    |> Response.structured(%{status: "ok", result: result})
  end

  defp error_response(message) do
    Response.tool()
    |> Response.structured(%{status: "error", error: message})
    |> Map.put(:isError, true)
  end

  defp parse_dimension_json(nil) do
    %{
      challenge_scores: [],
      challenge_composite: 0.0,
      unprompted_score: 0.0,
      unprompted_evidence: nil,
      composite_score: 0.0,
      raw: nil
    }
  end

  defp parse_dimension_json(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) ->
        %{
          challenge_scores: Map.get(map, "challenge_scores", []),
          challenge_composite: Map.get(map, "challenge_composite", 0.0),
          unprompted_score: Map.get(map, "unprompted_score", 0.0),
          unprompted_evidence: Map.get(map, "unprompted_evidence"),
          composite_score: Map.get(map, "composite_score", 0.0),
          raw: map
        }

      _ ->
        parse_dimension_json(nil)
    end
  end

  defp parse_dimension_json(_), do: parse_dimension_json(nil)

  defp parse_meta_json(nil),
    do: %{consistency: 0.5, grounding: 0.5, compliance: 0.5, reasoning: nil, raw: nil}

  defp parse_meta_json(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) ->
        %{
          consistency: Map.get(map, "consistency_score", 0.5),
          grounding: Map.get(map, "evidence_grounding_score", 0.5),
          compliance: Map.get(map, "rubric_compliance_score", 0.5),
          reasoning: Map.get(map, "reasoning"),
          raw: map
        }

      _ ->
        %{consistency: 0.5, grounding: 0.5, compliance: 0.5, reasoning: json, raw: nil}
    end
  end

  defp parse_meta_json(_),
    do: %{consistency: 0.5, grounding: 0.5, compliance: 0.5, reasoning: nil, raw: nil}

  defp p(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end
end
