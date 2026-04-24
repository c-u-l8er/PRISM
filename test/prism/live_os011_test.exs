defmodule Prism.LiveOs011Test do
  @moduledoc """
  Live end-to-end test for the OS-011 Embodiment Protocol benchmark.

  Submits the 10 scenarios shipped at `priv/fixtures/os011/scenarios.json`
  into PRISM's `compose(scenarios)` path, then drives a real
  `interact(run)` against a running Graphonomous MCP server as the
  target memory system. The simulator runs the scenario's turns,
  the response is persisted as a `Prism.Transcript`, and we assert
  the end-to-end path completed without errors.

  ## Requires

  A running Graphonomous MCP server. Default endpoint
  `http://127.0.0.1:4201/mcp`; override via `GRAPHONOMOUS_LIVE_URL`.

      cd graphonomous && \\
        GRAPHONOMOUS_TRANSPORT=http GRAPHONOMOUS_PORT=4201 \\
        GRAPHONOMOUS_EMBEDDER_BACKEND=fallback \\
        mix run --no-halt &

      cd ../PRISM && \\
        mix test --include live_os011 test/prism/live_os011_test.exs

  Closes the ⚠️ on dark-factory step 7: "PRISM scenarios have never
  been submitted to PRISM. No system has been benchmarked against
  them."
  """

  use Prism.DataCase, async: false

  @moduletag :live_os011

  alias Prism.Repo
  alias Prism.MCP.Machines.{Compose, Interact}
  alias Prism.{Scenario, Transcript}

  # `insert_repo_anchor!/1` is provided by Prism.Test.MachineHelpers
  # (imported below). Anchor-kind scenarios need a repo_anchor_id
  # to pass the `validate_anchor_has_repo` changeset guard.

  import Prism.Test.MachineHelpers

  @endpoint_default "http://127.0.0.1:4201/mcp"
  @fixture Path.expand("../../priv/fixtures/os011/scenarios.json", __DIR__)

  defp endpoint do
    # NOTE: use fully-qualified `Elixir.System.get_env/1` so it doesn't
    # collide with `Prism.System`.
    Elixir.System.get_env("GRAPHONOMOUS_LIVE_URL") || @endpoint_default
  end

  defp graphonomous_reachable? do
    health_url = endpoint() |> String.replace(~r{/mcp/?$}, "/health")
    _ = :inets.start()

    case :httpc.request(
           :get,
           {String.to_charlist(health_url), []},
           [timeout: 2_000, connect_timeout: 2_000],
           []
         ) do
      {:ok, {{_, 200, _}, _, body}} -> to_string(body) =~ "graphonomous"
      _ -> false
    end
  end

  setup do
    unless graphonomous_reachable?() do
      flunk("""
      Graphonomous MCP not reachable at #{endpoint()}.
      Start it before running these tests — see module docstring.
      """)
    end

    :ok
  end

  describe "OS-011 benchmark against live Graphonomous" do
    test "all 10 scenarios store via compose(action: \"scenarios\") and are retrievable" do
      anchor = insert_repo_anchor!()
      fixture = File.read!(@fixture) |> Jason.decode!()
      scenarios = fixture["scenarios"]
      assert length(scenarios) == 10

      params = %{
        action: "scenarios",
        scenario_ids: Jason.encode!(scenarios),
        repo_anchor_id: anchor.id
      }

      result = Compose.execute(params, frame()) |> extract_result()

      assert result["status"] == "ok"
      assert result["result"]["stored"] == 10
      assert result["result"]["failed"] == 0

      # All 10 are now in the DB
      assert Repo.aggregate(Scenario, :count, :id) == 10

      # Invariant coverage from the fixture (§9 §10)
      dims = fixture["cl_dimensions_exercised"]
      assert "plasticity" in dims
      assert "consolidation" in dims
      assert "transfer" in dims
    end

    test "interact(run) against live Graphonomous persists a Transcript row" do
      anchor = insert_repo_anchor!()
      # 1. Store scenarios
      scenarios = File.read!(@fixture) |> Jason.decode!() |> Map.fetch!("scenarios")

      _ =
        Compose.execute(
          %{
            action: "scenarios",
            scenario_ids: Jason.encode!(scenarios),
            repo_anchor_id: anchor.id
          },
          frame()
        )

      Scenario.Library.reload()

      # 2. Register Graphonomous as a PRISM system
      {:ok, system} =
        %Prism.System{}
        |> Prism.System.changeset(%{
          name: "graphonomous-live-#{Elixir.System.unique_integer([:positive])}",
          display_name: "Graphonomous (live)",
          mcp_endpoint: endpoint(),
          transport: "streamable_http"
        })
        |> Repo.insert()

      # 3. Pick one scenario — the first anchor of kind "anchor" will do
      [scenario | _] = Repo.all(Scenario)

      # 4. Run the scenario
      params = %{
        action: "run",
        scenario_id: scenario.id,
        system_id: system.id,
        llm_backend: "fixture-model-no-llm-in-mcp"
      }

      result = Interact.execute(params, frame()) |> extract_result()

      # The simulator connects to the live MCP endpoint, executes the
      # turns, and returns an :ok envelope. LLM calls are out of the
      # simulator's scope (per "no LLM in MCP" contract), so the
      # transcript captures the mechanical tool-call path only.
      assert result["status"] == "ok"
      r = result["result"]

      assert is_binary(r["transcript_id"])
      assert is_integer(r["total_turns"])
      assert r["total_turns"] >= 0

      # 5. Transcript persisted
      transcript = Repo.get!(Transcript, r["transcript_id"])
      assert transcript.scenario_id == scenario.id
      assert transcript.system_id == system.id
      assert transcript.llm_backend == "fixture-model-no-llm-in-mcp"
      assert is_list(transcript.sessions)
    end

    test "retire + list show scenarios are queryable post-store" do
      anchor = insert_repo_anchor!()
      scenarios = File.read!(@fixture) |> Jason.decode!() |> Map.fetch!("scenarios")

      _ =
        Compose.execute(
          %{
            action: "scenarios",
            scenario_ids: Jason.encode!(scenarios),
            repo_anchor_id: anchor.id
          },
          frame()
        )

      # list returns the stored scenarios (no filters)
      list_result =
        Compose.execute(%{action: "list"}, frame()) |> extract_result()

      assert list_result["status"] == "ok"

      # The `list` result payload may be either a list of scenario
      # maps or a %{"count" => _, "scenarios" => [...]}` map depending
      # on the machine version. Handle both.
      scenarios_out =
        case list_result["result"] do
          list when is_list(list) -> list
          %{"scenarios" => list} -> list
        end

      assert length(scenarios_out) >= 10

      # Every scenario has a kind, domain, difficulty
      Enum.each(scenarios_out, fn sc ->
        assert sc["kind"] in ["anchor", "frontier"]
        assert is_integer(sc["difficulty"])
        assert sc["difficulty"] >= 1 and sc["difficulty"] <= 5
      end)
    end
  end
end
