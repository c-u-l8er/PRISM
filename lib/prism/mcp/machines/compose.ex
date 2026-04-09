defmodule Prism.MCP.Machines.Compose do
  @moduledoc """
  Loop Phase 1: COMPOSE — "What should I test?"

  Unified scenario management machine for the PRISM evaluation loop.
  The agent calls this when building, validating, or managing test scenarios.

  PRISM is a pure data layer — the calling agent composes scenarios and passes
  them in as structured JSON. No LLM calls are made inside PRISM.

  Actions:
  - `scenarios`      — Store agent-composed scenarios (accepts JSON array)
  - `validate`       — CL coverage validation on stored scenarios
  - `list`           — List with filters (kind, domain, dimension, difficulty)
  - `get`            — Full scenario details + IRT params
  - `retire`         — Retire a scenario with reason
  - `byor_register`  — Register a personal repo anchor
  - `byor_discover`  — Auto-discover CL events in commit history
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  @valid_actions ~w(scenarios validate list get retire byor_register byor_discover)

  schema do
    field(:action, :string,
      required: true,
      description:
        "Compose action: scenarios | validate | list | get | retire | byor_register | byor_discover"
    )

    field(:repo_anchor_id, :string,
      description: "Repo anchor UUID (scenarios, byor_discover)"
    )

    # For 'scenarios' action: JSON array of scenario objects to store.
    # For 'validate' action: JSON array of scenario UUIDs.
    field(:scenario_ids, :string,
      description:
        "For scenarios action: JSON array of scenario objects (each with kind, domain, difficulty, persona, sessions, cl_challenges). For validate action: JSON array of scenario UUIDs."
    )

    # list
    field(:kind, :string, description: "Scenario kind filter: anchor | frontier (list)")
    field(:domain, :string, description: "Domain filter (list, byor_register)")
    field(:dimension, :string, description: "Dimension filter (list)")
    field(:difficulty, :number, description: "Difficulty filter 1-5 (list)")

    # get / retire
    field(:scenario_id, :string, description: "Scenario UUID (get, retire)")

    field(:reason, :string,
      description: "Retirement reason: saturated | ambiguous | too_hard | duplicate (retire)"
    )

    # byor_register
    field(:repo_url, :string, description: "Local git repo path (byor_register)")
    field(:commit_range, :string, description: "Commit range to analyze (byor_register)")
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

  # ── scenarios: store agent-composed scenarios ──────────────────────

  defp dispatch("scenarios", params, frame) do
    raw_data = p(params, :scenario_ids)
    anchor_id = p(params, :repo_anchor_id)

    scenarios_list =
      case parse_json_array(raw_data) do
        nil -> []
        list -> list
      end

    if scenarios_list == [] do
      {:reply, error_response("scenario_ids required: JSON array of scenario objects"), frame}
    else
      results =
        Enum.map(scenarios_list, fn raw ->
          attrs = normalize_scenario(raw, anchor_id)

          case %Prism.Scenario{}
               |> Prism.Scenario.changeset(attrs)
               |> Prism.Repo.insert() do
            {:ok, sc} ->
              %{id: sc.id, kind: sc.kind, domain: sc.domain, difficulty: sc.difficulty, status: "stored"}

            {:error, cs} ->
              %{status: "error", errors: inspect(cs.errors)}
          end
        end)

      stored = Enum.count(results, &(&1[:status] == "stored"))
      failed = Enum.count(results, &(&1[:status] == "error"))

      Prism.Scenario.Library.reload()

      {:reply,
       success_response(%{
         stored: stored,
         failed: failed,
         scenarios: results
       }), frame}
    end
  end

  # ── validate ───────────────────────────────────────────────────────

  defp dispatch("validate", params, frame) do
    ids = parse_json_array(p(params, :scenario_ids)) || []
    scenarios = Enum.map(ids, &Prism.Scenario.Library.get/1) |> Enum.filter(& &1)
    result = Prism.Scenario.Validator.validate_coverage(scenarios)
    {:reply, success_response(result), frame}
  end

  # ── list ───────────────────────────────────────────────────────────

  defp dispatch("list", params, frame) do
    filters = [
      kind: p(params, :kind),
      domain: p(params, :domain),
      dimension: p(params, :dimension),
      difficulty: p(params, :difficulty) && trunc(p(params, :difficulty))
    ]

    result = Prism.Scenario.Library.list(filters) |> Enum.map(&scenario_to_map/1)
    {:reply, success_response(result), frame}
  end

  # ── get ────────────────────────────────────────────────────────────

  defp dispatch("get", params, frame) do
    case p(params, :scenario_id) do
      nil ->
        {:reply, error_response("scenario_id required"), frame}

      id ->
        case Prism.Scenario.Library.get(id) do
          nil -> {:reply, error_response("scenario not found: #{id}"), frame}
          scenario -> {:reply, success_response(scenario_to_map(scenario)), frame}
        end
    end
  end

  # ── retire ─────────────────────────────────────────────────────────

  defp dispatch("retire", params, frame) do
    with id when not is_nil(id) <- p(params, :scenario_id),
         reason when not is_nil(reason) <- p(params, :reason),
         %Prism.Scenario{kind: kind} = scenario when kind != "anchor" <-
           Prism.Repo.get(Prism.Scenario, id),
         changeset <- Prism.Scenario.retire_changeset(scenario, reason),
         {:ok, updated} <- Prism.Repo.update(changeset) do
      Prism.Scenario.Library.reload()
      {:reply, success_response(%{retired: updated.id}), frame}
    else
      nil -> {:reply, error_response("scenario_id and reason required"), frame}
      %Prism.Scenario{kind: "anchor"} -> {:reply, error_response("cannot retire anchor scenarios"), frame}
      {:error, changeset} -> {:reply, error_response(inspect(changeset)), frame}
    end
  end

  # ── byor_register ──────────────────────────────────────────────────

  defp dispatch("byor_register", params, frame) do
    repo_url = p(params, :repo_url)
    domain = p(params, :domain) || "code"
    commit_range = p(params, :commit_range) || "HEAD~20..HEAD"

    if is_nil(repo_url) do
      {:reply, error_response("repo_url required for byor_register"), frame}
    else
      repo_path = if File.dir?(repo_url), do: repo_url, else: repo_url

      [from_ref, to_ref] =
        case String.split(commit_range, "..") do
          [f, t] -> [f, t]
          _ -> ["HEAD~20", "HEAD"]
        end

      from_hash = resolve_ref(repo_path, from_ref)
      to_hash = resolve_ref(repo_path, to_ref)

      total =
        case System.cmd("git", ["rev-list", "--count", "#{from_hash}..#{to_hash}"],
               cd: repo_path,
               stderr_to_stdout: true
             ) do
          {count_str, 0} -> count_str |> String.trim() |> String.to_integer()
          _ -> 20
        end

      key_events =
        case Prism.RepoAnchor.Walker.identify_events(repo_path, from_hash, to_hash) do
          {:ok, events} -> events
          _ -> []
        end

      attrs = %{
        repo_url: repo_url,
        license: "MIT",
        commit_range_from: from_hash,
        commit_range_to: to_hash,
        total_commits: max(total, 1),
        clone_path: repo_path,
        key_events: key_events
      }

      case %Prism.RepoAnchor{}
           |> Prism.RepoAnchor.changeset(attrs)
           |> Prism.Repo.insert() do
        {:ok, anchor} ->
          {:reply,
           success_response(%{
             id: anchor.id,
             repo_url: anchor.repo_url,
             total_commits: anchor.total_commits,
             key_events_count: length(key_events),
             key_events: key_events,
             domain: domain
           }), frame}

        {:error, changeset} ->
          {:reply, error_response("Failed to register: #{inspect(changeset.errors)}"), frame}
      end
    end
  end

  # ── byor_discover ──────────────────────────────────────────────────

  defp dispatch("byor_discover", params, frame) do
    case p(params, :repo_anchor_id) do
      nil ->
        {:reply, error_response("repo_anchor_id required"), frame}

      id ->
        case Prism.Repo.get(Prism.RepoAnchor, id) do
          nil ->
            {:reply, error_response("repo anchor not found: #{id}"), frame}

          %Prism.RepoAnchor{clone_path: path} = anchor when is_binary(path) ->
            case Prism.RepoAnchor.Walker.identify_events(
                   path,
                   anchor.commit_range_from,
                   anchor.commit_range_to
                 ) do
              {:ok, events} ->
                anchor
                |> Prism.RepoAnchor.changeset(%{key_events: events})
                |> Prism.Repo.update()

                {:reply, success_response(%{events: events, count: length(events)}), frame}

              {:error, reason} ->
                {:reply, error_response("Event discovery failed: #{inspect(reason)}"), frame}
            end

          _ ->
            {:reply, error_response("Anchor has no clone_path set"), frame}
        end
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp normalize_scenario(raw, anchor_id) do
    valid_domains = Prism.Domain.all_strings()
    domain = to_string(Map.get(raw, "domain", "code"))
    domain = if domain in valid_domains, do: domain, else: "code"

    diff = Map.get(raw, "difficulty", 3)
    diff = if is_number(diff), do: max(1, min(5, trunc(diff))), else: 3

    persona = Map.get(raw, "persona", %{})
    persona = if is_map(persona), do: persona, else: %{"description" => to_string(persona)}

    sessions = Map.get(raw, "sessions", [])
    sessions = if is_list(sessions), do: sessions, else: []

    cl = Map.get(raw, "cl_challenges", %{})
    cl = if is_map(cl), do: cl, else: %{}

    %{
      kind: Map.get(raw, "kind", "frontier"),
      domain: domain,
      difficulty: diff,
      persona: persona,
      sessions: sessions,
      cl_challenges: cl,
      repo_anchor_id: Map.get(raw, "repo_anchor_id") || anchor_id,
      validation_score: Map.get(raw, "validation_score")
    }
  end

  defp resolve_ref(repo_path, ref) do
    case System.cmd("git", ["rev-parse", ref], cd: repo_path, stderr_to_stdout: true) do
      {hash, 0} -> String.trim(hash)
      _ -> ref
    end
  end

  defp normalize_action(nil), do: nil
  defp normalize_action(v) when is_binary(v), do: v |> String.trim() |> String.downcase()
  defp normalize_action(v) when is_atom(v), do: Atom.to_string(v)
  defp normalize_action(_), do: nil

  defp parse_json_array(nil), do: nil
  defp parse_json_array(v) when is_list(v), do: v

  defp parse_json_array(v) when is_binary(v) do
    case Jason.decode(v) do
      {:ok, list} when is_list(list) -> list
      _ -> nil
    end
  end

  defp parse_json_array(_), do: nil

  defp success_response(result) do
    Response.tool()
    |> Response.structured(%{status: "ok", result: result})
  end

  defp error_response(message) do
    Response.tool()
    |> Response.structured(%{status: "error", error: message})
    |> Map.put(:isError, true)
  end

  defp scenario_to_map(%Prism.Scenario{} = s) do
    %{
      id: s.id,
      kind: s.kind,
      domain: s.domain,
      difficulty: s.difficulty,
      persona: s.persona,
      sessions: s.sessions,
      cl_challenges: s.cl_challenges,
      irt_difficulty_b: s.irt_difficulty_b,
      irt_discrimination_a: s.irt_discrimination_a,
      irt_guessing_c: s.irt_guessing_c,
      irt_calibrated: s.irt_calibrated,
      validation_score: s.validation_score,
      repo_anchor_id: s.repo_anchor_id,
      created_at: s.created_at && DateTime.to_iso8601(s.created_at)
    }
  end

  defp p(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end
end
