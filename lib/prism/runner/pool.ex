defmodule Prism.Runner.Pool do
  @moduledoc """
  Dynamic supervisor for concurrent benchmark execution workers.

  Each worker handles one (question × system) evaluation. The pool
  limits concurrency to avoid overwhelming memory systems or LLM APIs.
  """
  use DynamicSupervisor

  def start_link(opts) do
    pool_size = Keyword.get(opts, :pool_size, 4)
    DynamicSupervisor.start_link(__MODULE__, pool_size, name: __MODULE__)
  end

  @impl true
  def init(pool_size) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_children: pool_size
    )
  end

  @doc "Submit a task to the runner pool"
  def submit(fun) when is_function(fun, 0) do
    DynamicSupervisor.start_child(__MODULE__, {Task, fun})
  end

  @doc "Run a batch of tasks with bounded concurrency"
  def run_batch(tasks, opts \\ []) when is_list(tasks) do
    timeout = Keyword.get(opts, :timeout, 120_000)

    tasks
    |> Task.async_stream(fn task_fn -> task_fn.() end,
      max_concurrency: max_concurrency(),
      timeout: timeout,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> {:ok, result}
      {:exit, reason} -> {:error, reason}
    end)
  end

  defp max_concurrency do
    case DynamicSupervisor.count_children(__MODULE__) do
      %{specs: max} -> max
      _ -> 4
    end
  end
end
