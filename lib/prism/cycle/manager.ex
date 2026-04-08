defmodule Prism.Cycle.Manager do
  @moduledoc """
  Orchestrates the three-phase CL evaluation loop:

  Phase A (Generate): LLM produces benchmark questions from CL specs
  Phase B (Execute):  Run benchmarks against memory systems via MCP
  Phase C (Judge):    LLM judges answers, computes CL scores, feeds back

  The Manager is itself a continual learner:
  - Each cycle's gap analysis feeds into the next cycle's generation
  - Saturated questions are retired
  - Under-tested dimensions get more questions
  """
  use GenServer
  require Logger

  alias Prism.Benchmark.CLCategories
  alias Prism.LLM.Client

  defstruct [
    :current_cycle,
    :cl_weights,
    :generator_model,
    :judge_model,
    :registered_systems,
    :cycle_history
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      current_cycle: 0,
      cl_weights: CLCategories.default_weights(),
      generator_model: System.get_env("GENERATOR_MODEL", "claude-sonnet-4-20250514"),
      judge_model: System.get_env("JUDGE_MODEL", "gpt-4o"),
      registered_systems: [],
      cycle_history: []
    }

    Logger.info("[CL-Eval] Cycle Manager started. CL dimensions: #{length(CLCategories.ids())}")
    {:ok, state}
  end

  # ── Phase A: Generate ──────────────────────────────────────────────

  @doc """
  Generate a new benchmark suite.

  1. Build the generation prompt from CL category specs + gap analysis
  2. Call the LLM to generate questions + expected answers + rubrics
  3. Run a second LLM call to validate CL coverage of each question
  4. Store validated suite in Postgres
  """
  def generate_suite(opts \\ %{}) do
    GenServer.call(__MODULE__, {:generate_suite, opts}, :infinity)
  end

  @impl true
  def handle_call({:generate_suite, opts}, _from, state) do
    target = Map.get(opts, :target_questions, 200)
    cycle = state.current_cycle + 1

    Logger.info("[CL-Eval] Phase A: Generating suite for cycle #{cycle} (#{target} questions)")

    # Build generation prompt incorporating gap feedback from prior cycle
    prompt = build_generation_prompt(state, target)

    # Step 1: Generate questions via LLM
    case Client.generate(state.generator_model, prompt) do
      {:ok, raw_questions} ->
        # Step 2: Parse and validate structure
        questions = parse_generated_questions(raw_questions)

        # Step 3: CL coverage validation (different model to avoid bias)
        validated = validate_cl_coverage(questions, state.judge_model)

        # Step 4: Compute coverage scores
        coverage = compute_coverage_scores(validated)

        # Step 5: Store in database
        suite = store_suite(cycle, validated, coverage, state)

        emit_telemetry(:phase_a, :generate, %{
          cycle: cycle,
          total_generated: length(questions),
          total_validated: length(validated),
          coverage: coverage
        })

        {:reply, {:ok, suite}, %{state | current_cycle: cycle}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # ── Phase B: Execute ───────────────────────────────────────────────

  @doc """
  Run a benchmark suite against one or more memory systems.

  For each system:
  1. Reset the memory system
  2. Ingest any required context per question
  3. Query the system with the question
  4. Record the answer, retrieval context, and timing
  """
  def run_eval(suite_id, system, opts \\ %{}) do
    GenServer.call(__MODULE__, {:run_eval, suite_id, system, opts}, :infinity)
  end

  def run_matrix(suite_id, systems, models) do
    GenServer.call(__MODULE__, {:run_matrix, suite_id, systems, models}, :infinity)
  end

  @impl true
  def handle_call({:run_eval, suite_id, system, opts}, _from, state) do
    Logger.info("[CL-Eval] Phase B: Running suite #{suite_id} against #{system}")

    # Load suite questions
    questions = load_suite_questions(suite_id)

    # Connect to memory system via MCP
    {:ok, adapter} = connect_system(system)

    # Execute each question
    results =
      questions
      |> Enum.map(fn q ->
        execute_single_question(adapter, q, opts)
      end)

    # Store results
    run = store_run_results(suite_id, system, results, state)

    emit_telemetry(:phase_b, :execute, %{
      suite_id: suite_id,
      system: system,
      total_questions: length(questions),
      mean_retrieval_ms: mean_timing(results, :retrieval_ms)
    })

    {:reply, {:ok, run}, state}
  end

  @impl true
  def handle_call({:run_matrix, suite_id, systems, models}, _from, state) do
    Logger.info("[CL-Eval] Phase B: Matrix run — #{length(systems)} systems × #{length(models)} models")

    runs =
      for system <- systems, model <- models do
        {:ok, run} = do_run_eval(suite_id, system, %{llm_backend: model})
        run
      end

    {:reply, {:ok, runs}, state}
  end

  # ── Phase C: Judge + CL Score ──────────────────────────────────────

  @doc """
  Judge all answers in a run using the LLM judge.

  1. For each (question, answer) pair, ask the judge to score 0-1
  2. Aggregate scores by CL dimension using the question's CL tags
  3. Compute the 9-dimensional weighted CL score
  4. Update the leaderboard
  """
  def judge_run(run_id) do
    GenServer.call(__MODULE__, {:judge_run, run_id}, :infinity)
  end

  @impl true
  def handle_call({:judge_run, run_id}, _from, state) do
    Logger.info("[CL-Eval] Phase C: Judging run #{run_id}")

    # Load run results
    results = load_run_results(run_id)

    # Judge each answer
    judged =
      results
      |> Enum.map(fn result ->
        judge_single_answer(result, state.judge_model)
      end)

    # Aggregate by CL dimension
    cl_scores = aggregate_cl_scores(judged, state.cl_weights)

    # Update leaderboard
    update_leaderboard(run_id, cl_scores, state)

    emit_telemetry(:phase_c, :judge, %{
      run_id: run_id,
      cl_scores: cl_scores,
      weighted_total: compute_weighted_total(cl_scores, state.cl_weights)
    })

    {:reply, {:ok, cl_scores}, state}
  end

  # ── CL Meta-Loop ──────────────────────────────────────────────────

  @doc """
  Analyze gaps in the current cycle and prepare feedback for the next.

  1. Which CL dimensions had the fewest questions?
  2. Which questions did ALL systems ace? (saturation → retire)
  3. Which questions did NO system answer? (too hard → adjust)
  4. Which dimensions showed the least variance? (not discriminating)
  """
  def analyze_gaps(cycle) do
    GenServer.call(__MODULE__, {:analyze_gaps, cycle})
  end

  def advance_cycle do
    GenServer.call(__MODULE__, :advance_cycle, :infinity)
  end

  @impl true
  def handle_call({:analyze_gaps, cycle}, _from, state) do
    gaps = do_gap_analysis(cycle)
    {:reply, {:ok, gaps}, state}
  end

  @impl true
  def handle_call(:advance_cycle, _from, state) do
    # Run gap analysis on current cycle
    {:ok, gaps} = do_gap_analysis(state.current_cycle)

    # Record the feedback
    feedback = %{
      from_cycle: state.current_cycle,
      to_cycle: state.current_cycle + 1,
      gap_analysis: gaps,
      timestamp: DateTime.utc_now()
    }

    new_history = [feedback | state.cycle_history]

    Logger.info("""
    [CL-Eval] Advancing to cycle #{state.current_cycle + 1}
    Gap analysis: #{inspect(gaps.under_tested_dims)}
    Saturated questions: #{length(gaps.saturated_questions)}
    """)

    {:reply, {:ok, feedback}, %{state | cycle_history: new_history}}
  end

  # ── Private helpers ────────────────────────────────────────────────

  defp build_generation_prompt(state, target_count) do
    categories = CLCategories.all()
    gaps = if state.current_cycle > 0, do: get_prior_gaps(state), else: nil

    """
    You are a benchmark designer for Continual Learning evaluation of AI agent memory systems.

    Generate #{target_count} benchmark questions that test the following 9 CL dimensions:

    #{format_categories(categories)}

    #{if gaps, do: format_gap_feedback(gaps), else: ""}

    For each question, provide:
    1. question_text: The question to ask the memory system
    2. expected_answer: The correct/ideal answer
    3. rubric: Scoring criteria (0-1 scale) for the LLM judge
    4. cl_categories: Which CL dimensions this tests (with relative weights)
    5. difficulty: 1-5 scale
    6. requires_state: Whether prior ingestion is needed
    7. ingestion_context: If requires_state, what to ingest first (as a sequence of sessions)

    Target distribution across CL dimensions (by weight):
    #{format_target_distribution(state.cl_weights)}

    Respond in JSON array format.
    """
  end

  defp validate_cl_coverage(questions, judge_model) do
    # Second LLM pass to validate each question's CL tagging
    prompt = """
    You are a CL evaluation expert. For each question below, verify:
    1. Does it actually test the claimed CL dimensions?
    2. Is the difficulty rating accurate?
    3. Is the rubric clear and unambiguous?
    4. Is the expected answer correct?

    Score each question's CL coverage quality 0-1.
    Reject questions scoring below 0.6.

    Questions: #{Jason.encode!(questions)}
    """

    case Client.generate(judge_model, prompt) do
      {:ok, validation} -> filter_validated(questions, validation)
      {:error, _} -> questions  # Fallback: keep all if validation fails
    end
  end

  defp compute_coverage_scores(questions) do
    # For each CL dimension, count questions and compute coverage density
    CLCategories.ids()
    |> Map.new(fn dim ->
      matching = Enum.filter(questions, fn q ->
        q.cl_categories |> Map.keys() |> Enum.member?(dim)
      end)

      {dim, %{
        count: length(matching),
        mean_difficulty: mean_difficulty(matching),
        weight_coverage: sum_weights(matching, dim)
      }}
    end)
  end

  defp aggregate_cl_scores(judged_results, cl_weights) do
    # For each CL dimension, aggregate the judged scores
    CLCategories.ids()
    |> Map.new(fn dim ->
      relevant = Enum.filter(judged_results, fn r ->
        Map.has_key?(r.cl_dimensions, dim)
      end)

      if relevant == [] do
        {dim, nil}
      else
        scores = Enum.map(relevant, fn r ->
          r.judge_score * Map.get(r.cl_dimensions, dim, 0)
        end)
        {dim, Enum.sum(scores) / length(scores)}
      end
    end)
  end

  defp compute_weighted_total(cl_scores, weights) do
    Enum.reduce(cl_scores, 0.0, fn {dim, score}, acc ->
      if score, do: acc + score * Map.get(weights, dim, 0), else: acc
    end)
  end

  defp do_gap_analysis(cycle) do
    # Analyze the current cycle for gaps
    %{
      under_tested_dims: find_under_tested_dims(cycle),
      saturated_questions: find_saturated_questions(cycle),
      too_hard_questions: find_too_hard_questions(cycle),
      low_variance_dims: find_low_variance_dims(cycle),
      recommended_adjustments: generate_recommendations(cycle)
    }
  end

  defp execute_single_question(adapter, question, _opts) do
    # 1. Ingest context if needed
    ingestion_ms =
      if question.requires_state do
        {time, _} = :timer.tc(fn ->
          adapter.ingest(question.ingestion_context)
        end)
        div(time, 1000)
      else
        0
      end

    # 2. Query
    {retrieval_time, {answer, context}} = :timer.tc(fn ->
      adapter.query(question.question_text)
    end)

    %{
      question_id: question.id,
      raw_answer: answer,
      retrieval_context: context,
      ingestion_ms: ingestion_ms,
      retrieval_ms: div(retrieval_time, 1000),
      answer_ms: div(retrieval_time, 1000)
    }
  end

  defp judge_single_answer(result, judge_model) do
    prompt = """
    You are judging an answer from an AI memory system.

    Question: #{result.question.question_text}
    Expected Answer: #{result.question.expected_answer}
    Actual Answer: #{result.raw_answer}
    Scoring Rubric: #{Jason.encode!(result.question.rubric)}

    Score the answer 0.0 to 1.0 based on the rubric.
    Explain your reasoning briefly.
    Also score each CL dimension that this question tests.

    Respond in JSON: {"score": 0.X, "explanation": "...", "cl_dimensions": {"dim": score}}
    """

    case Client.generate(judge_model, prompt) do
      {:ok, judgment} -> Map.merge(result, parse_judgment(judgment))
      {:error, _} -> Map.put(result, :judge_score, 0.0)
    end
  end

  defp emit_telemetry(phase, action, measurements) do
    :telemetry.execute(
      [:prism, phase, action],
      measurements,
      %{timestamp: DateTime.utc_now()}
    )
  end

  # Placeholder implementations for DB operations
  defp store_suite(_cycle, questions, coverage, _state), do: %{id: UUID.uuid4(), questions: questions, coverage: coverage}
  defp store_run_results(_suite_id, _system, results, _state), do: %{id: UUID.uuid4(), results: results}
  defp load_suite_questions(_suite_id), do: []
  defp load_run_results(_run_id), do: []
  defp connect_system(_system), do: {:ok, %{}}
  defp update_leaderboard(_run_id, _scores, _state), do: :ok
  defp get_prior_gaps(_state), do: nil
  defp find_under_tested_dims(_cycle), do: []
  defp find_saturated_questions(_cycle), do: []
  defp find_too_hard_questions(_cycle), do: []
  defp find_low_variance_dims(_cycle), do: []
  defp generate_recommendations(_cycle), do: []
  defp do_run_eval(suite_id, system, opts), do: {:ok, %{id: UUID.uuid4()}}
  defp format_categories(cats), do: Enum.map_join(cats, "\n", &"- #{&1.name} (#{&1.weight}): #{&1.description}")
  defp format_gap_feedback(gaps), do: "Previous cycle gaps: #{inspect(gaps)}"
  defp format_target_distribution(weights), do: Enum.map_join(weights, "\n", fn {k, v} -> "  #{k}: #{v}" end)
  defp parse_generated_questions(raw), do: []
  defp filter_validated(questions, _validation), do: questions
  defp mean_difficulty(questions), do: 3.0
  defp sum_weights(questions, _dim), do: 1.0
  defp mean_timing(results, _field), do: 0
  defp parse_judgment(_raw), do: %{judge_score: 0.5, cl_dimensions: %{}}
end
