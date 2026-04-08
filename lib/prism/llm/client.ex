defmodule Prism.LLM.Client do
  @moduledoc """
  Multi-provider LLM client. Supports Anthropic, OpenAI, and Google APIs.

  Used for:
  - Phase A: Generating benchmark questions (generator_model)
  - Phase C: Judging answers (judge_model)
  - Meta-loop: Gap analysis and refinement proposals

  Uses different models for generation vs. judging to avoid self-bias.
  """
  require Logger

  @anthropic_url "https://api.anthropic.com/v1/messages"
  @openai_url "https://api.openai.com/v1/chat/completions"

  @doc """
  Generate a completion from the specified model.

  Automatically routes to the correct API based on model name:
  - "claude-*" → Anthropic API
  - "gpt-*" → OpenAI API
  - "gemini-*" → Google API
  """
  def generate(model, prompt, opts \\ []) do
    max_tokens = Keyword.get(opts, :max_tokens, 4096)
    temperature = Keyword.get(opts, :temperature, 0.7)
    system = Keyword.get(opts, :system, nil)

    {time_us, result} = :timer.tc(fn ->
      cond do
        String.starts_with?(model, "claude") -> call_anthropic(model, prompt, system, max_tokens, temperature)
        String.starts_with?(model, "gpt") -> call_openai(model, prompt, system, max_tokens, temperature)
        true -> {:error, "Unsupported model provider: #{model}"}
      end
    end)

    Logger.debug("[LLM] #{model} responded in #{div(time_us, 1000)}ms")

    :telemetry.execute(
      [:prism, :llm, :call],
      %{duration_ms: div(time_us, 1000)},
      %{model: model, prompt_length: String.length(prompt)}
    )

    result
  end

  @doc "Generate and parse as JSON"
  def generate_json(model, prompt, opts \\ []) do
    case generate(model, prompt, opts) do
      {:ok, text} ->
        # Strip markdown code fences if present
        cleaned = text
        |> String.replace(~r/```json\s*/, "")
        |> String.replace(~r/```\s*$/, "")
        |> String.trim()

        case Jason.decode(cleaned) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, _} -> {:error, "Failed to parse LLM response as JSON: #{String.slice(cleaned, 0, 200)}"}
        end

      error -> error
    end
  end

  # ── Anthropic API ──────────────────────────────────────────────────

  defp call_anthropic(model, prompt, system, max_tokens, temperature) do
    api_key = System.get_env("ANTHROPIC_API_KEY") || raise "ANTHROPIC_API_KEY not set"

    body = %{
      model: model,
      max_tokens: max_tokens,
      temperature: temperature,
      messages: [%{role: "user", content: prompt}]
    }

    body = if system, do: Map.put(body, :system, system), else: body

    case Req.post(@anthropic_url,
      json: body,
      headers: [
        {"x-api-key", api_key},
        {"anthropic-version", "2023-06-01"},
        {"content-type", "application/json"}
      ],
      receive_timeout: 120_000
    ) do
      {:ok, %{status: 200, body: %{"content" => [%{"text" => text} | _]}}} ->
        {:ok, text}

      {:ok, %{status: status, body: body}} ->
        {:error, "Anthropic API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Anthropic API request failed: #{inspect(reason)}"}
    end
  end

  # ── OpenAI API ─────────────────────────────────────────────────────

  defp call_openai(model, prompt, system, max_tokens, temperature) do
    api_key = System.get_env("OPENAI_API_KEY") || raise "OPENAI_API_KEY not set"

    messages = if system do
      [%{role: "system", content: system}, %{role: "user", content: prompt}]
    else
      [%{role: "user", content: prompt}]
    end

    case Req.post(@openai_url,
      json: %{
        model: model,
        messages: messages,
        max_tokens: max_tokens,
        temperature: temperature
      },
      headers: [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ],
      receive_timeout: 120_000
    ) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => text}} | _]}}} ->
        {:ok, text}

      {:ok, %{status: status, body: body}} ->
        {:error, "OpenAI API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "OpenAI API request failed: #{inspect(reason)}"}
    end
  end
end
