defmodule Prism.Cycle.Manager do
  @moduledoc """
  Orchestrates the 4-phase PRISM evaluation loop.

  ```
  Phase 1: Compose → Phase 2: Interact → Phase 3: Observe → Phase 4: Reflect
       ↑                                                          │
       └────────────────── Scenario Evolution ────────────────────┘
  ```

  Each cycle produces scenarios, runs them against memory systems via
  the User Simulator, judges transcripts through three layers, and
  evolves the scenario suite for the next cycle.
  """

  use GenServer
  require Logger

  alias Prism.Scenario.{Composer, Library, Validator}
  alias Prism.IRT.Calibrator

  defstruct [
    :current_cycle,
    :current_suite_id,
    :status,
    :phase,
    :config,
    started_at: nil,
    phase_history: []
  ]

  @type phase :: :idle | :composing | :interacting | :observing | :reflecting
  @type status :: :idle | :running | :paused | :completed | :failed

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get the current cycle state."
  @spec state() :: map()
  def state, do: GenServer.call(__MODULE__, :state)

  @doc "Advance to the next cycle — runs all 4 phases."
  @spec advance_cycle(keyword()) :: {:ok, map()} | {:error, term()}
  def advance_cycle(opts \\ []) do
    GenServer.call(__MODULE__, {:advance_cycle, opts}, 600_000)
  end

  @doc "Run a specific phase manually."
  @spec run_phase(phase(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_phase(phase, opts \\ []) do
    GenServer.call(__MODULE__, {:run_phase, phase, opts}, 300_000)
  end

  @doc "Get gap analysis for the current or specified cycle."
  @spec analyze_gaps(integer() | nil) :: {:ok, map()} | {:error, term()}
  def analyze_gaps(cycle \\ nil) do
    GenServer.call(__MODULE__, {:analyze_gaps, cycle})
  end

  @doc "Get cycle history."
  @spec history() :: [map()]
  def history, do: GenServer.call(__MODULE__, :history)

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    config = %{
      generator_model: Keyword.get(opts, :generator_model, "claude-sonnet-4-20250514"),
      validator_model: Keyword.get(opts, :validator_model, "gpt-4o"),
      judge_model: Keyword.get(opts, :judge_model, "claude-sonnet-4-20250514"),
      meta_judge_model: Keyword.get(opts, :meta_judge_model, "gpt-4o"),
      simulator_model: Keyword.get(opts, :simulator_model, "claude-sonnet-4-20250514"),
      target_scenarios: Keyword.get(opts, :target_scenarios, 20),
      anchor_ratio: Keyword.get(opts, :anchor_ratio, 0.35)
    }

    state = %__MODULE__{
      current_cycle: 0,
      status: :idle,
      phase: :idle,
      config: config
    }

    Logger.info("[PRISM] Cycle Manager initialized")
    {:ok, state}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, Map.from_struct(state), state}
  end

  @impl true
  def handle_call({:advance_cycle, opts}, _from, state) do
    if state.status == :running do
      {:reply, {:error, :cycle_already_running}, state}
    else
      new_cycle = state.current_cycle + 1
      Logger.info("[PRISM] ═══════ Starting Cycle #{new_cycle} ═══════")

      state = %{
        state
        | current_cycle: new_cycle,
          status: :running,
          started_at: DateTime.utc_now()
      }

      case run_full_cycle(state, opts) do
        {:ok, result, final_state} ->
          Logger.info("[PRISM] ═══════ Cycle #{new_cycle} Complete ═══════")
          final_state = %{final_state | status: :completed, phase: :idle}
          {:reply, {:ok, result}, final_state}

        {:error, reason, failed_state} ->
          Logger.error("[PRISM] Cycle #{new_cycle} failed: #{inspect(reason)}")
          failed_state = %{failed_state | status: :failed}
          {:reply, {:error, reason}, failed_state}
      end
    end
  end

  @impl true
  def handle_call({:run_phase, phase, opts}, _from, state) do
    case execute_phase(phase, state, opts) do
      {:ok, result, new_state} ->
        {:reply, {:ok, result}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:analyze_gaps, cycle_num}, _from, state) do
    cycle = cycle_num || state.current_cycle
    gaps = do_gap_analysis(cycle)
    {:reply, {:ok, gaps}, state}
  end

  @impl true
  def handle_call(:history, _from, state) do
    {:reply, state.phase_history, state}
  end

  # --- Phase Execution ---

  defp run_full_cycle(state, opts) do
    with {:ok, compose_result, state} <- execute_phase(:composing, state, opts),
         {:ok, interact_result, state} <- execute_phase(:interacting, state, opts),
         {:ok, observe_result, state} <- execute_phase(:observing, state, opts),
         {:ok, reflect_result, state} <- execute_phase(:reflecting, state, opts) do
      result = %{
        cycle: state.current_cycle,
        compose: compose_result,
        interact: interact_result,
        observe: observe_result,
        reflect: reflect_result
      }

      {:ok, result, state}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp execute_phase(:composing, state, opts) do
    Logger.info("[PRISM] Phase 1: Compose")
    state = %{state | phase: :composing}
    start = System.monotonic_time(:millisecond)

    # Get gap analysis from prior cycle
    prior_gaps =
      if state.current_cycle > 1,
        do: do_gap_analysis(state.current_cycle - 1),
        else: %{gaps: []}

    focus_dims = extract_focus_dimensions(prior_gaps)
    focus_domains = extract_focus_domains(prior_gaps)

    result =
      case Keyword.get(opts, :repo_anchor) do
        nil ->
          scenarios = Library.list()
          coverage = Validator.validate_coverage(scenarios)
          %{scenarios: length(scenarios), coverage: coverage, source: :library}

        anchor ->
          case Composer.compose(anchor,
                 count: state.config.target_scenarios,
                 focus_dimensions: focus_dims,
                 focus_domains: focus_domains,
                 generator_model: state.config.generator_model,
                 validator_model: state.config.validator_model
               ) do
            {:ok, %{status: "prompt_ready"} = prompt_result} ->
              %{prompt: prompt_result, source: :prompt_ready}

            {:error, reason} ->
              %{error: reason, source: :failed}
          end
      end

    duration = System.monotonic_time(:millisecond) - start
    emit_telemetry(:compose, duration)
    state = record_phase(state, :composing, result, duration)
    {:ok, result, state}
  end

  defp execute_phase(:interacting, state, opts) do
    Logger.info("[PRISM] Phase 2: Interact")
    state = %{state | phase: :interacting}
    start = System.monotonic_time(:millisecond)

    systems = Keyword.get(opts, :systems, [])
    llm_backend = Keyword.get(opts, :llm_backend, state.config.simulator_model)
    scenarios = Library.list()

    results =
      for system_id <- systems, scenario <- scenarios do
        case Prism.Simulator.Engine.interact(scenario, %{}, system_id, llm_backend) do
          {:ok, transcript} -> {:ok, transcript}
          {:error, reason} -> {:error, {system_id, scenario.id, reason}}
        end
      end

    successes = Enum.count(results, &match?({:ok, _}, &1))
    failures = Enum.count(results, &match?({:error, _}, &1))

    result = %{
      total_interactions: length(results),
      successes: successes,
      failures: failures,
      systems: length(systems)
    }

    duration = System.monotonic_time(:millisecond) - start
    emit_telemetry(:interact, duration)
    state = record_phase(state, :interacting, result, duration)
    {:ok, result, state}
  end

  defp execute_phase(:observing, state, opts) do
    Logger.info("[PRISM] Phase 3: Observe (3-layer judging)")
    state = %{state | phase: :observing}
    start = System.monotonic_time(:millisecond)

    judge_model = Keyword.get(opts, :judge_model, state.config.judge_model)
    meta_judge_model = Keyword.get(opts, :meta_judge_model, state.config.meta_judge_model)

    # TODO: Load transcripts from DB for this cycle's run, judge each one
    result = %{
      judge_model: judge_model,
      meta_judge_model: meta_judge_model,
      l2_judgments: 0,
      l3_meta_judgments: 0,
      accept_rate: nil,
      flag_rate: nil,
      reject_rate: nil
    }

    duration = System.monotonic_time(:millisecond) - start
    emit_telemetry(:observe, duration)
    state = record_phase(state, :observing, result, duration)
    {:ok, result, state}
  end

  defp execute_phase(:reflecting, state, _opts) do
    Logger.info("[PRISM] Phase 4: Reflect")
    state = %{state | phase: :reflecting}
    start = System.monotonic_time(:millisecond)

    gaps = do_gap_analysis(state.current_cycle)

    # IRT recalibration (with empty observations for now)
    Calibrator.recalibrate([])

    result = %{
      gaps: gaps,
      irt_recalibrated: true,
      cycle: state.current_cycle
    }

    duration = System.monotonic_time(:millisecond) - start
    emit_telemetry(:reflect, duration)
    state = record_phase(state, :reflecting, result, duration)
    {:ok, result, state}
  end

  defp execute_phase(unknown, _state, _opts) do
    {:error, {:unknown_phase, unknown}}
  end

  # --- Gap Analysis ---

  defp do_gap_analysis(_cycle) do
    scenarios = Library.list()
    coverage = Validator.validate_coverage(scenarios)

    %{
      dimension_coverage: coverage.dimension_coverage,
      domain_coverage: coverage.domain_coverage,
      gaps: coverage.gaps,
      overall_adequate: coverage.overall_adequate,
      recommendations: generate_recommendations(coverage.gaps)
    }
  end

  defp generate_recommendations(gaps) do
    Enum.map(gaps, fn gap ->
      %{
        type: gap.type,
        action: gap.recommendation,
        priority: if(gap.type == :dimension_gap, do: :high, else: :medium)
      }
    end)
  end

  defp extract_focus_dimensions(%{gaps: gaps}) do
    gaps
    |> Enum.filter(&(&1.type == :dimension_gap))
    |> Enum.map(& &1.dimension)
  end

  defp extract_focus_dimensions(_), do: []

  defp extract_focus_domains(%{gaps: gaps}) do
    gaps
    |> Enum.filter(&(&1.type == :domain_gap))
    |> Enum.map(& &1.domain)
  end

  defp extract_focus_domains(_), do: []

  defp record_phase(state, phase, result, duration_ms) do
    entry = %{
      phase: phase,
      cycle: state.current_cycle,
      result: result,
      duration_ms: duration_ms,
      timestamp: DateTime.utc_now()
    }

    %{state | phase_history: [entry | state.phase_history]}
  end

  defp emit_telemetry(phase, duration) do
    :telemetry.execute(
      [:prism, :phase, phase, :duration],
      %{duration: duration},
      %{phase: phase}
    )
  end
end
