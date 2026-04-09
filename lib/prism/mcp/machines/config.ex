defmodule Prism.MCP.Machines.Config do
  @moduledoc """
  Admin machine (outside the loop): setup and configuration.

  Actions:
  - `set_weights`     — Update 9-dimension weight vector
  - `register_system` — Register memory system + MCP endpoint
  - `list_systems`    — List registered systems
  - `get_config`      — Current full configuration
  - `create_profile`  — Define custom task profile

  Replaces: set_cl_weights, register_system, list_systems,
            get_config, create_task_profile
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  @valid_actions ~w(set_weights register_system list_systems get_config create_profile)

  schema do
    field(:action, :string,
      required: true,
      description: "Config action: set_weights | register_system | list_systems | get_config | create_profile"
    )

    # set_weights
    field(:weights, :string, description: "JSON object of dimension → weight, must sum to 1.0 (set_weights)")

    # register_system
    field(:name, :string, description: "System name (register_system, create_profile)")
    field(:display_name, :string, description: "Display name (register_system)")
    field(:mcp_endpoint, :string, description: "MCP endpoint (register_system)")
    field(:transport, :string, description: "Transport type: stdio | sse (register_system)")

    # create_profile
    field(:dimension_priorities, :string,
      description: "JSON object of dimension → priority mapping (create_profile)"
    )

    field(:domains, :string, description: "JSON array of target domains (create_profile)")
  end

  @impl true
  def execute(params, frame) do
    action = params |> p(:action) |> normalize_action()

    if action in @valid_actions do
      dispatch(action, params, frame)
    else
      {:reply,
       error_response(
         "Invalid action '#{inspect(p(params, :action))}'. Must be one of: #{Enum.join(@valid_actions, ", ")}"
       ), frame}
    end
  end

  defp dispatch("set_weights", params, frame) do
    case parse_json_object(p(params, :weights)) do
      nil ->
        {:reply, error_response("weights JSON object required"), frame}

      weights ->
        atom_weights =
          Map.new(weights, fn {k, v} ->
            {String.to_existing_atom(k), v}
          end)

        case Prism.Benchmark.CLCategories.validate_weights(atom_weights) do
          :ok -> {:reply, success_response(%{weights: atom_weights, status: "updated"}), frame}
          {:error, reason} -> {:reply, error_response(inspect(reason)), frame}
        end
    end
  rescue
    ArgumentError -> {:reply, error_response("invalid dimension name in weights"), frame}
  end

  defp dispatch("register_system", params, frame) do
    attrs = %{
      name: p(params, :name),
      display_name: p(params, :display_name) || p(params, :name),
      mcp_endpoint: p(params, :mcp_endpoint),
      transport: p(params, :transport)
    }

    changeset = Prism.System.changeset(%Prism.System{}, attrs)

    case Prism.Repo.insert(changeset) do
      {:ok, system} -> {:reply, success_response(%{id: system.id, name: system.name}), frame}
      {:error, changeset} -> {:reply, error_response(inspect(changeset.errors)), frame}
    end
  end

  defp dispatch("list_systems", _params, frame) do
    systems = Prism.Repo.all(Prism.System)

    result =
      Enum.map(systems, fn s ->
        %{id: s.id, name: s.name, display_name: s.display_name, transport: s.transport}
      end)

    {:reply, success_response(result), frame}
  end

  defp dispatch("get_config", _params, frame) do
    state = Prism.Cycle.Manager.state()

    result = %{
      cycle: state.current_cycle,
      status: state.status,
      phase: state.phase,
      config: state.config,
      weights: Prism.Benchmark.CLCategories.default_weights(),
      domains: Prism.Domain.all_strings(),
      machines: 6,
      storage_backend: Application.get_env(:prism, :storage_backend, :sqlite)
    }

    {:reply, success_response(result), frame}
  end

  defp dispatch("create_profile", params, frame) do
    name = p(params, :name)
    priorities_json = p(params, :dimension_priorities)
    domains_json = p(params, :domains)

    with name when not is_nil(name) <- name,
         priorities when is_map(priorities) <- parse_json_object(priorities_json),
         domains when is_list(domains) <- parse_json_array(domains_json) do
      # Validate that all priority keys are valid dimensions
      valid_dims = Prism.Benchmark.CLCategories.dimension_strings()

      invalid_dims =
        priorities
        |> Map.keys()
        |> Enum.reject(&(&1 in valid_dims))

      if invalid_dims != [] do
        {:reply, error_response("Invalid dimensions: #{inspect(invalid_dims)}"), frame}
      else
        profile = %{
          id: Ecto.UUID.generate(),
          name: name,
          dimension_priorities: priorities,
          domains: domains,
          created_at: DateTime.utc_now()
        }

        # Store in ETS for session lifetime
        :ets.insert(:prism_task_profiles, {profile.id, profile})

        {:reply, success_response(profile), frame}
      end
    else
      nil -> {:reply, error_response("name, dimension_priorities (JSON object), and domains (JSON array) required"), frame}
      _ -> {:reply, error_response("dimension_priorities must be a JSON object, domains must be a JSON array"), frame}
    end
  end

  # -- Helpers --

  defp normalize_action(nil), do: nil
  defp normalize_action(v) when is_binary(v), do: v |> String.trim() |> String.downcase()
  defp normalize_action(v) when is_atom(v), do: Atom.to_string(v)
  defp normalize_action(_), do: nil

  defp parse_json_object(nil), do: nil
  defp parse_json_object(v) when is_map(v), do: v

  defp parse_json_object(v) when is_binary(v) do
    case Jason.decode(v) do
      {:ok, map} when is_map(map) -> map
      _ -> nil
    end
  end

  defp parse_json_object(_), do: nil

  defp parse_json_array(nil), do: nil

  defp parse_json_array(v) when is_binary(v) do
    case Jason.decode(v) do
      {:ok, list} when is_list(list) -> list
      _ -> nil
    end
  end

  defp parse_json_array(v) when is_list(v), do: v
  defp parse_json_array(_), do: nil

  defp success_response(result) do
    Response.tool()
    |> Response.structured(%{status: "ok", result: result})
  end

  defp error_response(message) do
    Response.tool()
    |> Response.structured(%{status: "error", error: message})
    |> Map.put(:isError, true)
  end

  defp p(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end
end
