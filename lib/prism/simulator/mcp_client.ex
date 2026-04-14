defmodule Prism.Simulator.McpClient do
  @moduledoc """
  Lightweight MCP client for PRISM's simulator engine.

  Connects to a target memory system's MCP endpoint (Streamable HTTP transport),
  performs the initialize handshake, and calls tools.
  """

  require Logger

  @doc """
  Connect to an MCP server and perform the initialize handshake.
  Returns a connection map with the session ID for subsequent tool calls.
  """
  @spec connect(String.t()) :: {:ok, map()} | {:error, term()}
  def connect(mcp_endpoint) do
    # 1. Initialize
    init_body = %{
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: %{
        protocolVersion: "2025-03-26",
        capabilities: %{},
        clientInfo: %{name: "prism-simulator", version: "0.1.0"}
      }
    }

    case post_json(mcp_endpoint, init_body, nil) do
      {:ok, %{status: status, body: body, headers: headers}} when status in 200..299 ->
        session_id = extract_session_id(headers, body)

        # 2. Send notifications/initialized
        notif_body = %{jsonrpc: "2.0", method: "notifications/initialized"}
        post_json(mcp_endpoint, notif_body, session_id)

        conn = %{
          endpoint: mcp_endpoint,
          session_id: session_id
        }

        Logger.info("[PRISM McpClient] Connected to #{mcp_endpoint}, session=#{session_id || "none"}")
        {:ok, conn}

      {:ok, %{status: status, body: body}} ->
        {:error, "MCP initialize failed: HTTP #{status} — #{inspect(body)}"}

      {:error, reason} ->
        {:error, "MCP connect failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Call a tool on the connected MCP server.
  Returns the parsed result or error.
  """
  @spec call_tool(map(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def call_tool(conn, tool_name, args) do
    body = %{
      jsonrpc: "2.0",
      id: System.unique_integer([:positive]),
      method: "tools/call",
      params: %{name: tool_name, arguments: args}
    }

    case post_json(conn.endpoint, body, conn.session_id) do
      {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
        case resp_body do
          %{"result" => result} ->
            unwrap_mcp_result(result)

          %{"error" => error} ->
            {:error, error["message"] || inspect(error)}

          other ->
            {:ok, other}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, "MCP tool call failed: HTTP #{status} — #{inspect(body)}"}

      {:error, reason} ->
        {:error, "MCP tool call failed: #{inspect(reason)}"}
    end
  end

  # Unwrap MCP content envelope — prefer structuredContent, fall back to text parsing
  defp unwrap_mcp_result(%{"structuredContent" => sc}) when is_map(sc), do: {:ok, sc}

  defp unwrap_mcp_result(%{"content" => content}) when is_list(content) do
    text_item = Enum.find(content, fn c -> c["type"] == "text" && c["text"] end)

    if text_item do
      case Jason.decode(text_item["text"]) do
        {:ok, parsed} -> {:ok, parsed}
        _ -> {:ok, %{"raw" => text_item["text"]}}
      end
    else
      {:ok, %{"content" => content}}
    end
  end

  defp unwrap_mcp_result(other), do: {:ok, other}

  # Extract session ID from Mcp-Session-Id header or response body
  defp extract_session_id(headers, body) do
    # Check headers first (standard MCP)
    header_sid =
      headers
      |> Enum.find_value(fn
        {"mcp-session-id", val} -> val
        {key, val} when is_binary(key) ->
          if String.downcase(key) == "mcp-session-id", do: val
        _ -> nil
      end)

    # Fall back to body field (some servers embed it)
    header_sid || get_in(body, ["_mcpSessionId"])
  end

  defp post_json(url, body, session_id) do
    headers = [{"content-type", "application/json"}, {"accept", "application/json, text/event-stream"}]
    headers = if session_id, do: [{"mcp-session-id", session_id} | headers], else: headers

    case Req.post(url, json: body, headers: headers, receive_timeout: 30_000) do
      {:ok, %Req.Response{status: status, headers: resp_headers, body: resp_body}} ->
        # Flatten header list values
        flat_headers =
          Enum.flat_map(resp_headers, fn
            {k, vals} when is_list(vals) -> Enum.map(vals, &{k, &1})
            {k, v} -> [{k, v}]
          end)

        {:ok, %{status: status, body: resp_body, headers: flat_headers}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
