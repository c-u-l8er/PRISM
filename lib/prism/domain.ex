defmodule Prism.Domain do
  @moduledoc """
  Domain vocabulary for PRISM scenarios.

  Every scenario is tagged with a domain from this controlled vocabulary.
  Domains enable domain-filtered leaderboards, cross-domain transfer testing,
  and 3D capability surfaces (CL dimension × domain × system).

  Domain is a first-class field on prism_scenarios, not a derived tag.
  Judges receive domain context in their rubrics — medical CL has different
  expectations than personal CL.
  """

  @type t ::
          :code
          | :medical
          | :business
          | :personal
          | :research
          | :creative
          | :legal
          | :operations

  @domains %{
    code: %{
      label: "Code",
      description: "Software engineering, debugging, architecture decisions",
      example_challenges: [
        "API refactors",
        "dependency changes",
        "pattern transfer across modules"
      ]
    },
    medical: %{
      label: "Medical",
      description: "Clinical knowledge, drug interactions, patient history",
      example_challenges: [
        "guideline updates",
        "drug interaction contradictions",
        "treatment protocol changes"
      ]
    },
    business: %{
      label: "Business",
      description: "Strategy, financials, competitive intelligence",
      example_challenges: [
        "market shifts",
        "competitor changes",
        "forecast updates"
      ]
    },
    personal: %{
      label: "Personal",
      description: "User preferences, life events, relationships",
      example_challenges: [
        "preference changes",
        "life event updates",
        "habit tracking"
      ]
    },
    research: %{
      label: "Research",
      description: "Academic papers, experiments, literature review",
      example_challenges: [
        "replication failures",
        "methodology updates",
        "citation chain tracking"
      ]
    },
    creative: %{
      label: "Creative",
      description: "Writing projects, design iterations, brainstorming history",
      example_challenges: [
        "style evolution",
        "concept refinement",
        "version history tracking"
      ]
    },
    legal: %{
      label: "Legal",
      description: "Case law, compliance requirements, contract terms",
      example_challenges: [
        "regulation changes",
        "precedent updates",
        "jurisdiction conflicts"
      ]
    },
    operations: %{
      label: "Operations",
      description: "Infrastructure, incident response, runbooks",
      example_challenges: [
        "config changes",
        "post-mortem learnings",
        "runbook updates"
      ]
    }
  }

  @valid_atoms Map.keys(@domains)
  @valid_strings Enum.map(@valid_atoms, &Atom.to_string/1)

  @doc "Returns the full domain catalog as a map of atom → metadata."
  @spec catalog() :: map()
  def catalog, do: @domains

  @doc "Returns the list of valid domain atoms."
  @spec all() :: [t()]
  def all, do: @valid_atoms

  @doc "Returns the list of valid domain strings."
  @spec all_strings() :: [String.t()]
  def all_strings, do: @valid_strings

  @doc "Validates and normalizes a domain value to an atom."
  @spec validate(atom() | String.t()) :: {:ok, t()} | {:error, String.t()}
  def validate(domain) when is_atom(domain) do
    if domain in @valid_atoms do
      {:ok, domain}
    else
      {:error, "Invalid domain: #{inspect(domain)}. Valid domains: #{inspect(@valid_atoms)}"}
    end
  end

  def validate(domain) when is_binary(domain) do
    if domain in @valid_strings do
      {:ok, String.to_existing_atom(domain)}
    else
      {:error, "Invalid domain: #{inspect(domain)}. Valid domains: #{inspect(@valid_strings)}"}
    end
  end

  def validate(other) do
    {:error, "Invalid domain type: #{inspect(other)}. Expected atom or string."}
  end

  @doc "Returns metadata for a specific domain."
  @spec get(t()) :: map() | nil
  def get(domain) when domain in @valid_atoms, do: Map.get(@domains, domain)
  def get(_), do: nil

  @doc "Returns the human-readable label for a domain."
  @spec label(t()) :: String.t() | nil
  def label(domain) when domain in @valid_atoms do
    @domains |> Map.get(domain) |> Map.get(:label)
  end

  def label(_), do: nil

  @doc """
  Validates a list of focus domains for scenario composition.
  Returns {:ok, domains} with normalized atoms, or {:error, reason}.
  """
  @spec validate_focus(list()) :: {:ok, [t()]} | {:error, String.t()}
  def validate_focus(domains) when is_list(domains) do
    results = Enum.map(domains, &validate/1)
    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      {:ok, Enum.map(results, fn {:ok, d} -> d end)}
    else
      messages = Enum.map(errors, fn {:error, msg} -> msg end)
      {:error, Enum.join(messages, "; ")}
    end
  end

  def validate_focus(_), do: {:error, "Expected a list of domains"}
end
