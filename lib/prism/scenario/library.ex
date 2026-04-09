defmodule Prism.Scenario.Library do
  @moduledoc """
  GenServer caching scenarios and their IRT parameters.

  Provides fast access to active scenarios, filtered by kind, domain,
  dimension, and difficulty. Caches in ETS for read-heavy access patterns.
  """

  use GenServer
  require Logger

  @table :prism_scenario_library

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get all active scenarios, optionally filtered."
  @spec list(keyword()) :: [Prism.Scenario.t()]
  def list(filters \\ []) do
    all_scenarios()
    |> filter_by(:kind, Keyword.get(filters, :kind))
    |> filter_by(:domain, Keyword.get(filters, :domain))
    |> filter_by(:difficulty, Keyword.get(filters, :difficulty))
    |> filter_by_dimension(Keyword.get(filters, :dimension))
  end

  @doc "Get a single scenario by ID."
  @spec get(binary()) :: Prism.Scenario.t() | nil
  def get(id) do
    case :ets.lookup(@table, id) do
      [{^id, scenario}] -> scenario
      [] -> nil
    end
  end

  @doc "Get anchor scenarios only."
  @spec anchors() :: [Prism.Scenario.t()]
  def anchors, do: list(kind: "anchor")

  @doc "Get frontier scenarios only."
  @spec frontiers() :: [Prism.Scenario.t()]
  def frontiers, do: list(kind: "frontier")

  @doc "Reload scenarios from database."
  @spec reload() :: :ok
  def reload, do: GenServer.call(__MODULE__, :reload)

  @doc "Get coverage stats: dimension × domain counts."
  @spec coverage_stats() :: map()
  def coverage_stats do
    GenServer.call(__MODULE__, :coverage_stats)
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    Logger.info("[PRISM] Scenario library initialized")
    {:ok, %{table: table}, {:continue, :load}}
  end

  @impl true
  def handle_continue(:load, state) do
    load_from_db()
    {:noreply, state}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    load_from_db()
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:coverage_stats, _from, state) do
    stats =
      all_scenarios()
      |> Enum.reduce(%{}, fn scenario, acc ->
        dims = Prism.Scenario.dimensions(scenario)
        domain = scenario.domain

        Enum.reduce(dims, acc, fn dim, inner_acc ->
          key = {dim, domain}
          Map.update(inner_acc, key, 1, &(&1 + 1))
        end)
      end)

    {:reply, stats, state}
  end

  # --- Internal ---

  defp load_from_db do
    # Load active scenarios from Ecto
    import Ecto.Query

    scenarios =
      Prism.Scenario
      |> where([s], is_nil(s.retired_at))
      |> Prism.Repo.all()

    # Clear and reload ETS
    :ets.delete_all_objects(@table)

    Enum.each(scenarios, fn scenario ->
      :ets.insert(@table, {scenario.id, scenario})
    end)

    Logger.info("[PRISM] Loaded #{length(scenarios)} active scenarios into library")
  rescue
    error ->
      Logger.warning("[PRISM] Could not load scenarios from DB: #{inspect(error)}")
  end

  defp all_scenarios do
    :ets.tab2list(@table)
    |> Enum.map(fn {_id, scenario} -> scenario end)
  rescue
    ArgumentError -> []
  end

  defp filter_by(scenarios, _field, nil), do: scenarios

  defp filter_by(scenarios, field, value) do
    Enum.filter(scenarios, fn s -> Map.get(s, field) == value end)
  end

  defp filter_by_dimension(scenarios, nil), do: scenarios

  defp filter_by_dimension(scenarios, dimension) do
    dim_str = to_string(dimension)

    Enum.filter(scenarios, fn s ->
      dims = Prism.Scenario.dimensions(s)
      dim_str in Enum.map(dims, &to_string/1)
    end)
  end
end
