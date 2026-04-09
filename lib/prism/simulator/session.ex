defmodule Prism.Simulator.Session do
  @moduledoc """
  GenServer managing one scenario execution session.

  Each session runs a single scenario against a single memory system,
  producing a transcript. Managed by the Simulator.Supervisor.
  """

  use GenServer
  require Logger

  defstruct [
    :scenario,
    :system_id,
    :llm_backend,
    :conn,
    :opts,
    :transcript,
    :status,
    :started_at,
    :completed_at,
    :caller
  ]

  # --- Client API ---

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @doc "Start the interaction asynchronously."
  def run(pid) do
    GenServer.cast(pid, :run)
  end

  @doc "Get current session status."
  def status(pid) do
    GenServer.call(pid, :status)
  end

  @doc "Get the transcript (only available after completion)."
  def transcript(pid) do
    GenServer.call(pid, :transcript)
  end

  # --- Server Callbacks ---

  @impl true
  def init(args) do
    state = %__MODULE__{
      scenario: args.scenario,
      system_id: args.system_id,
      llm_backend: args.llm_backend,
      conn: args.conn,
      opts: Map.get(args, :opts, []),
      caller: Map.get(args, :caller),
      status: :initialized,
      started_at: nil,
      completed_at: nil,
      transcript: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_cast(:run, state) do
    state = %{state | status: :running, started_at: DateTime.utc_now()}

    Logger.info("[PRISM] Session starting: scenario=#{state.scenario.id}")

    case Prism.Simulator.Engine.interact(
           state.scenario,
           state.conn,
           state.system_id,
           state.llm_backend,
           state.opts
         ) do
      {:ok, transcript} ->
        new_state = %{
          state
          | status: :completed,
            transcript: transcript,
            completed_at: DateTime.utc_now()
        }

        notify_caller(new_state)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("[PRISM] Session failed: #{inspect(reason)}")
        new_state = %{state | status: :failed, completed_at: DateTime.utc_now()}
        notify_caller(new_state)
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_call(:transcript, _from, state) do
    {:reply, state.transcript, state}
  end

  defp notify_caller(%{caller: nil}), do: :ok

  defp notify_caller(%{caller: caller, status: status, transcript: transcript}) do
    send(caller, {:session_complete, self(), status, transcript})
  end
end
