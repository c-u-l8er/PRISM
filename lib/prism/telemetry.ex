defmodule Prism.Telemetry do
  @moduledoc "Telemetry supervisor for PRISM metrics."
  use Supervisor

  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  def init(_arg) do
    children = [{:telemetry_poller, measurements: periodic_measurements(), period: 10_000}]
    Supervisor.init(children, strategy: :one_for_one)
  end

  defp periodic_measurements do
    [{__MODULE__, :emit_stats, []}]
  end

  def emit_stats do
    :telemetry.execute([:prism, :system, :memory], %{
      total: :erlang.memory(:total),
      processes: :erlang.memory(:processes)
    })
  end
end
