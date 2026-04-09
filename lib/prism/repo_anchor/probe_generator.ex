defmodule Prism.RepoAnchor.ProbeGenerator do
  @moduledoc """
  LLM-driven generation of CL probe questions from commit diffs.

  Produces probes with verifiable ground truth — the expected answer
  is derived directly from the code at a specific commit, not from
  author opinion.
  """

  require Logger

  @doc """
  Generate CL probes from a commit diff.

  Returns probes with ground truth references (commit, file, answer).
  """
  @spec generate_probes(String.t() | nil, map(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def generate_probes(diff, commit_info, opts \\ [])
  def generate_probes("", _commit_info, _opts), do: {:error, :empty_diff}
  def generate_probes(nil, _commit_info, _opts), do: {:error, :nil_diff}

  def generate_probes(diff, commit_info, opts) do
    model = Keyword.get(opts, :model, "claude-sonnet-4-20250514")
    max_probes = Keyword.get(opts, :max_probes, 3)

    prompt = build_probe_prompt(diff, commit_info, max_probes)

    # Return the prompt for the agent to evaluate externally.
    {:ok,
     [
       %{
         prompt: prompt,
         model: model,
         commit: Map.get(commit_info, :hash),
         status: "prompt_ready"
       }
     ]}
  end

  @doc """
  Generate probes for multiple commits in a range.
  """
  @spec generate_for_range(String.t(), [map()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def generate_for_range(repo_path, commits, opts \\ []) do
    probes =
      commits
      |> Enum.flat_map(fn commit ->
        case Prism.RepoAnchor.Walker.get_diff(repo_path, commit.hash) do
          {:ok, diff} ->
            case generate_probes(diff, commit, opts) do
              {:ok, p} -> p
              {:error, _} -> []
            end

          {:error, _} ->
            []
        end
      end)

    {:ok, probes}
  end

  # --- Internal ---

  defp build_probe_prompt(diff, commit_info, max_probes) do
    """
    You are a PRISM probe generator. Analyze this commit diff and generate
    CL (Continual Learning) probe questions with verifiable ground truth.

    Commit: #{Map.get(commit_info, :hash, "unknown")}
    Message: #{Map.get(commit_info, :message, "unknown")}
    Author: #{Map.get(commit_info, :author, "unknown")}

    Diff:
    ```
    #{String.slice(diff, 0, 8000)}
    ```

    Generate up to #{max_probes} probe questions. For each probe:
    1. Identify what CL dimension this change tests
    2. Write a natural question a developer might ask
    3. Provide the ground truth answer verifiable from the code
    4. Reference the specific file and commit

    Return JSON:
    {
      "probes": [
        {
          "dimension": "knowledge_update",
          "question": "What token library does the auth module use?",
          "ground_truth_answer": "Joken — Guardian was replaced",
          "ground_truth_file": "lib/app/auth.ex",
          "ground_truth_commit": "abc123",
          "difficulty": 2
        }
      ]
    }
    """
  end

  @doc """
  Normalize a raw probe map from LLM output into a structured probe.

  Called by the agent after running the probe generation prompt.
  """
  @spec normalize_probe(map(), map()) :: map()
  def normalize_probe(raw, commit_info) do
    %{
      dimension: Map.get(raw, "dimension", "stability"),
      question: Map.get(raw, "question", ""),
      ground_truth_answer: Map.get(raw, "ground_truth_answer", ""),
      ground_truth_file: Map.get(raw, "ground_truth_file", ""),
      ground_truth_commit: Map.get(raw, "ground_truth_commit", Map.get(commit_info, :hash)),
      difficulty: Map.get(raw, "difficulty", 3)
    }
  end
end
