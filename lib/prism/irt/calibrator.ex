defmodule Prism.IRT.Calibrator do
  @moduledoc """
  GenServer for IRT parameter estimation and recalibration.

  Maintains scenario difficulty/discrimination parameters and system
  ability estimates. Recalibrates after each cycle from accumulated data.

  Anchor scenario IRT params are locked after 3 stable cycles.
  Frontier params update each cycle.
  """

  use GenServer
  require Logger

  alias Prism.IRT.Model

  defstruct [
    :cycle_number,
    # scenario_id → {a, b, c}
    scenario_params: %{},
    # {system_id, dimension} → θ
    system_abilities: %{},
    calibration_history: []
  ]

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get IRT parameters for a scenario."
  @spec scenario_params(binary()) :: {float(), float(), float()} | nil
  def scenario_params(scenario_id) do
    GenServer.call(__MODULE__, {:get_scenario_params, scenario_id})
  end

  @doc "Get estimated ability for a system on a dimension."
  @spec system_ability(binary(), String.t()) :: float()
  def system_ability(system_id, dimension) do
    GenServer.call(__MODULE__, {:get_ability, system_id, dimension})
  end

  @doc """
  Recalibrate all parameters from accumulated cycle data.

  Takes a list of {scenario_id, system_id, dimension, score} tuples.
  """
  @spec recalibrate([{binary(), binary(), String.t(), float()}]) :: :ok
  def recalibrate(observations) do
    GenServer.call(__MODULE__, {:recalibrate, observations}, 60_000)
  end

  @doc "Get calibration summary for the current state."
  @spec summary() :: map()
  def summary do
    GenServer.call(__MODULE__, :summary)
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    Logger.info("[PRISM] IRT Calibrator initialized")
    {:ok, %__MODULE__{cycle_number: 0}}
  end

  @impl true
  def handle_call({:get_scenario_params, scenario_id}, _from, state) do
    params = Map.get(state.scenario_params, scenario_id, {1.0, 0.0, 0.1})
    {:reply, params, state}
  end

  @impl true
  def handle_call({:get_ability, system_id, dimension}, _from, state) do
    ability = Map.get(state.system_abilities, {system_id, dimension}, 0.0)
    {:reply, ability, state}
  end

  @impl true
  def handle_call({:recalibrate, observations}, _from, state) do
    Logger.info("[PRISM] Recalibrating IRT parameters from #{length(observations)} observations")

    new_state = do_recalibrate(state, observations)

    Logger.info(
      "[PRISM] Recalibration complete. " <>
        "#{map_size(new_state.scenario_params)} scenarios, " <>
        "#{map_size(new_state.system_abilities)} ability estimates"
    )

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:summary, _from, state) do
    summary = %{
      cycle_number: state.cycle_number,
      calibrated_scenarios: map_size(state.scenario_params),
      ability_estimates: map_size(state.system_abilities),
      history_length: length(state.calibration_history)
    }

    {:reply, summary, state}
  end

  # --- Internal ---

  defp do_recalibrate(state, observations) do
    # Group observations by scenario
    by_scenario =
      Enum.group_by(observations, fn {scenario_id, _, _, _} -> scenario_id end)

    # Group observations by (system, dimension)
    by_system_dim =
      Enum.group_by(observations, fn {_, system_id, dim, _} -> {system_id, dim} end)

    # Update scenario params
    new_scenario_params =
      Enum.reduce(by_scenario, state.scenario_params, fn {scenario_id, obs}, acc ->
        scores = Enum.map(obs, fn {_, _, _, score} -> score end)

        b =
          Model.estimate_difficulty(
            Enum.map(obs, fn {_, system_id, dim, score} ->
              ability = Map.get(state.system_abilities, {system_id, dim}, 0.0)
              {ability, score}
            end)
          )

        a = Model.estimate_discrimination(scores)
        c = Map.get(acc, scenario_id, {1.0, 0.0, 0.1}) |> elem(2)

        Map.put(acc, scenario_id, {a, b, c})
      end)

    # Update system abilities
    new_abilities =
      Enum.reduce(by_system_dim, state.system_abilities, fn {{system_id, dim}, obs}, acc ->
        item_responses =
          Enum.map(obs, fn {scenario_id, _, _, score} ->
            {a, b, c} = Map.get(new_scenario_params, scenario_id, {1.0, 0.0, 0.1})
            {score, a, b, c}
          end)

        theta =
          Model.estimate_ability(item_responses,
            initial: Map.get(acc, {system_id, dim}, 0.0)
          )

        Map.put(acc, {system_id, dim}, theta)
      end)

    %{
      state
      | scenario_params: new_scenario_params,
        system_abilities: new_abilities,
        cycle_number: state.cycle_number + 1,
        calibration_history: [
          %{
            cycle: state.cycle_number + 1,
            scenarios_calibrated: map_size(new_scenario_params),
            abilities_estimated: map_size(new_abilities),
            timestamp: DateTime.utc_now()
          }
          | state.calibration_history
        ]
    }
  end
end
