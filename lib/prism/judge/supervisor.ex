defmodule Prism.Judge.Supervisor do
  @moduledoc """
  DynamicSupervisor for judging tasks (Layer 2 and Layer 3).
  """

  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one, max_children: 100)
  end

  @doc "Start a Layer 2 dimension judging task."
  def start_l2_judge(transcript, dimension, judge_model, opts \\ []) do
    task =
      Task.Supervisor.async_nolink(
        __MODULE__,
        Prism.Judge.DimensionWorker,
        :judge,
        [transcript, dimension, judge_model, opts]
      )

    {:ok, task}
  end

  @doc "Start a Layer 3 meta-judging task."
  def start_l3_judge(judgment, transcript, meta_judge_model, opts \\ []) do
    task =
      Task.Supervisor.async_nolink(
        __MODULE__,
        Prism.Judge.MetaWorker,
        :meta_judge,
        [judgment, transcript, meta_judge_model, opts]
      )

    {:ok, task}
  end
end
