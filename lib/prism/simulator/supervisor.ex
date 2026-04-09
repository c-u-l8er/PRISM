defmodule Prism.Simulator.Supervisor do
  @moduledoc """
  DynamicSupervisor for simulator sessions.

  Manages concurrent scenario executions across multiple memory systems.
  """

  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one, max_children: 50)
  end

  @doc "Start a new simulator session."
  def start_session(args) do
    DynamicSupervisor.start_child(__MODULE__, {Prism.Simulator.Session, args})
  end

  @doc "Count active sessions."
  def active_count do
    DynamicSupervisor.count_children(__MODULE__).active
  end
end
