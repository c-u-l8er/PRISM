defmodule Prism.MCP.Adapter do
  @moduledoc """
  Behavior that every memory system adapter must implement.

  Each adapter translates PRISM's standardized operations into the
  specific MCP tool calls for that memory system.

  Example: The Graphonomous adapter maps:
  - ingest/2 → store_node + store_edge
  - query/2 → retrieve_context
  - interact/3 → multi-turn session via native tools
  - forget/2 → forget_node
  - feedback/2 → learn_from_outcome
  - reset/1 → (delete all nodes)
  """

  @doc "Connect to the memory system's MCP server"
  @callback connect(config :: map()) :: {:ok, state :: term()} | {:error, term()}

  @doc "Ingest a sequence of conversation sessions into the memory system"
  @callback ingest(state :: term(), sessions :: [map()]) :: {:ok, map()} | {:error, term()}

  @doc "Query the memory system with a question, return answer + retrieval context"
  @callback query(state :: term(), question :: String.t()) ::
              {:ok, answer :: String.t(), context :: map()} | {:error, term()}

  @doc """
  Multi-turn session interaction.

  Executes a series of turns (ingestions, queries, feedback) as a single
  session against the memory system. Returns the full interaction trace
  including tool calls, retrieval contexts, and timing.

  This is the primary interface for Phase 2 (Interact).
  """
  @callback interact(state :: term(), session :: map(), opts :: keyword()) ::
              {:ok, trace :: map()} | {:error, term()}

  @doc "Provide outcome feedback to the memory system (helpful/unhelpful)"
  @callback feedback(state :: term(), feedback :: map()) :: {:ok, map()} | {:error, term()}

  @doc "Request the system to forget specific information"
  @callback forget(state :: term(), target :: map()) :: {:ok, map()} | {:error, term()}

  @doc "Reset the memory system to clean state"
  @callback reset(state :: term()) :: :ok | {:error, term()}

  @doc "Get system stats (node count, edge count, latency, etc.)"
  @callback stats(state :: term()) :: map()

  @doc "Disconnect from the memory system"
  @callback disconnect(state :: term()) :: :ok

  @doc "List available MCP tools on this system"
  @callback list_tools(state :: term()) :: {:ok, [map()]} | {:error, term()}

  @optional_callbacks [forget: 2, feedback: 2, list_tools: 1]
end
