defmodule Prism.Sequence.Runner do
  @moduledoc """
  Executes scenario sequences WITHOUT resetting memory between passes.

  This is the core of closed-loop testing. A sequence runs S1→S2→S3
  against the SAME memory state, measuring whether the system's retrieval
  quality improves from outcome feedback between passes.
  """

  require Logger

  alias Prism.Sequence

  @doc """
  Execute a scenario sequence against a memory system.

  Unlike `run_interaction`, this does NOT reset memory between scenarios.
  The system accumulates knowledge and feedback across all passes.

  Returns transcripts for each pass plus sequence-level metrics.
  """
  @spec run(Sequence.t(), binary(), String.t(), keyword()) ::
          {:ok, %{transcripts: [Transcript.t()], metrics: map()}} | {:error, term()}
  def run(%Sequence{scenario_ids: scenario_ids} = sequence, system_id, llm_backend, opts \\ []) do
    Logger.info("[PRISM] Running sequence '#{sequence.name}' (#{length(scenario_ids)} passes)",
      system_id: system_id,
      llm_backend: llm_backend
    )

    adapter = Keyword.get(opts, :adapter)

    with {:ok, conn} <- connect_system(system_id, adapter),
         {:ok, results} <- run_passes(scenario_ids, conn, system_id, llm_backend, opts) do
      transcripts = Enum.map(results, & &1.transcript)
      pass_scores = Enum.map(results, & &1.pass_scores)

      metrics = Prism.Sequence.Scorer.compute_metrics(pass_scores)

      Logger.info("[PRISM] Sequence complete. Loop closure rate: #{metrics.loop_closure_rate}",
        sequence_id: sequence.id
      )

      {:ok, %{transcripts: transcripts, metrics: metrics}}
    end
  end

  # Run each scenario in order, WITHOUT resetting memory
  defp run_passes(scenario_ids, conn, system_id, llm_backend, opts) do
    results =
      scenario_ids
      |> Enum.with_index(1)
      |> Enum.reduce_while({:ok, []}, fn {scenario_id, pass_num}, {:ok, acc} ->
        Logger.info("[PRISM] Running pass #{pass_num}/#{length(scenario_ids)}")

        case run_single_pass(scenario_id, conn, system_id, llm_backend, pass_num, opts) do
          {:ok, result} ->
            {:cont, {:ok, acc ++ [result]}}

          {:error, reason} ->
            Logger.error("[PRISM] Pass #{pass_num} failed: #{inspect(reason)}")
            {:halt, {:error, {:pass_failed, pass_num, reason}}}
        end
      end)

    results
  end

  defp run_single_pass(scenario_id, conn, system_id, llm_backend, pass_num, opts) do
    scenario = Prism.Scenario.Library.get(scenario_id)

    if scenario == nil do
      {:error, {:scenario_not_found, scenario_id}}
    else
      # Execute interaction WITHOUT reset
      case Prism.Simulator.Engine.interact(scenario, conn, system_id, llm_backend, opts) do
        {:ok, transcript} ->
          # Compute per-dimension scores for this pass
          pass_scores = extract_pass_scores(transcript)
          {:ok, %{transcript: transcript, pass_scores: pass_scores, pass_number: pass_num}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp connect_system(system_id, adapter) do
    if adapter do
      adapter.connect(%{system_id: system_id})
    else
      # Default: look up system config from DB
      case Prism.Repo.get(Prism.System, system_id) do
        nil -> {:error, :system_not_found}
        system -> {:ok, %{system: system, pid: self()}}
      end
    end
  end

  # Extract dimension scores from transcript for pass-level analysis
  defp extract_pass_scores(_transcript) do
    # Placeholder: actual scoring happens in Phase 3 (Observe)
    # For sequence scoring, we use the L2 judgment scores after they're computed
    %{}
  end
end
