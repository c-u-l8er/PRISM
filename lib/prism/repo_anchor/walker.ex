defmodule Prism.RepoAnchor.Walker do
  @moduledoc """
  Walks git commit history and extracts diffs/files at each revision.

  Used during Phase 1 (Compose) to analyze repos for CL-relevant events,
  and during Phase 2 (Interact) to feed repo state into memory systems.
  """

  require Logger

  @doc """
  Clone a repository to a local path.
  """
  @spec clone(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def clone(repo_url, dest_path) do
    Logger.info("[PRISM] Cloning #{repo_url} to #{dest_path}")

    case System.cmd("git", ["clone", "--bare", repo_url, dest_path], stderr_to_stdout: true) do
      {_output, 0} -> {:ok, dest_path}
      {output, code} -> {:error, {:clone_failed, code, output}}
    end
  end

  @doc """
  List commits in a range, ordered chronologically.
  Returns list of %{hash, message, author, date, files_changed}.
  """
  @spec list_commits(String.t(), String.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def list_commits(repo_path, from_hash, to_hash) do
    format = "%H\t%s\t%an\t%aI"
    range = "#{from_hash}..#{to_hash}"

    case System.cmd("git", ["log", "--format=#{format}", "--reverse", range],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        commits =
          output
          |> String.trim()
          |> String.split("\n", trim: true)
          |> Enum.map(&parse_commit_line/1)

        {:ok, commits}

      {output, code} ->
        {:error, {:git_log_failed, code, output}}
    end
  end

  @doc """
  Get the diff for a specific commit.
  """
  @spec get_diff(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def get_diff(repo_path, commit_hash) do
    case System.cmd("git", ["diff", "#{commit_hash}~1..#{commit_hash}"],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, output}
      {output, code} -> {:error, {:git_diff_failed, code, output}}
    end
  end

  @doc """
  Get file content at a specific revision.
  """
  @spec get_file_at_rev(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def get_file_at_rev(repo_path, commit_hash, file_path) do
    case System.cmd("git", ["show", "#{commit_hash}:#{file_path}"],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, output}
      {output, code} -> {:error, {:git_show_failed, code, output}}
    end
  end

  @doc """
  Get files changed in a specific commit.
  """
  @spec files_changed(String.t(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def files_changed(repo_path, commit_hash) do
    case System.cmd("git", ["diff-tree", "--no-commit-id", "-r", "--name-only", commit_hash],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        files = output |> String.trim() |> String.split("\n", trim: true)
        {:ok, files}

      {output, code} ->
        {:error, {:git_diff_tree_failed, code, output}}
    end
  end

  @doc """
  Identify CL-relevant events in a commit range.
  Analyzes diffs and commit messages for refactors, contradictions,
  cross-module patterns, etc.
  """
  @spec identify_events(String.t(), String.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def identify_events(repo_path, from_hash, to_hash) do
    with {:ok, commits} <- list_commits(repo_path, from_hash, to_hash) do
      events =
        commits
        |> Enum.flat_map(fn commit ->
          case classify_commit(repo_path, commit) do
            {:ok, event} -> [event]
            :skip -> []
          end
        end)

      {:ok, events}
    end
  end

  # --- Internal ---

  defp parse_commit_line(line) do
    case String.split(line, "\t", parts: 4) do
      [hash, message, author, date] ->
        %{
          hash: hash,
          message: String.trim(message),
          author: author,
          date: date
        }

      _ ->
        %{hash: "unknown", message: line, author: "unknown", date: "unknown"}
    end
  end

  defp classify_commit(repo_path, commit) do
    msg = String.downcase(commit.message)

    type =
      cond do
        String.contains?(msg, ["refactor", "rename", "restructure", "reorganize"]) ->
          "refactor"

        String.contains?(msg, ["replace", "swap", "migrate", "switch from"]) ->
          "dependency_change"

        String.contains?(msg, ["move", "relocate"]) ->
          "file_move"

        String.contains?(msg, ["fix", "bug", "patch", "hotfix"]) ->
          "bug_fix"

        String.contains?(msg, ["add", "new", "feature", "implement"]) ->
          "new_feature"

        String.contains?(msg, ["update", "change", "modify"]) ->
          "api_change"

        true ->
          nil
      end

    if type do
      files =
        case files_changed(repo_path, commit.hash) do
          {:ok, f} -> f
          _ -> []
        end

      {:ok,
       %{
         "commit" => commit.hash,
         "type" => type,
         "description" => commit.message,
         "author" => commit.author,
         "date" => commit.date,
         "files_changed" => files
       }}
    else
      :skip
    end
  end
end
