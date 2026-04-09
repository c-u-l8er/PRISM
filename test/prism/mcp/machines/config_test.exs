defmodule Prism.MCP.Machines.ConfigTest do
  use Prism.DataCase

  alias Prism.MCP.Machines.Config
  import Prism.Test.MachineHelpers

  describe "invalid action" do
    test "returns error for unknown action" do
      result = Config.execute(%{action: "bogus"}, frame()) |> extract_result()
      assert result["status"] == "error"
      assert result["error"] =~ "Invalid action"
    end
  end

  describe "register_system" do
    test "registers a new memory system" do
      result =
        Config.execute(
          %{
            action: "register_system",
            name: "test-sys-#{System.unique_integer([:positive])}",
            display_name: "Test System",
            mcp_endpoint: "stdio://test",
            transport: "stdio"
          },
          frame()
        )
        |> extract_result()

      assert result["status"] == "ok"
      assert result["result"]["id"]
      assert result["result"]["name"] =~ "test-sys"
    end

    test "fails on duplicate name" do
      name = "dup-sys-#{System.unique_integer([:positive])}"

      Config.execute(
        %{action: "register_system", name: name, mcp_endpoint: "stdio://test", transport: "stdio"},
        frame()
      )

      result =
        Config.execute(
          %{action: "register_system", name: name, mcp_endpoint: "stdio://test2", transport: "stdio"},
          frame()
        )
        |> extract_result()

      assert result["status"] == "error"
    end
  end

  describe "list_systems" do
    test "lists all registered systems" do
      insert_system!()

      result = Config.execute(%{action: "list_systems"}, frame()) |> extract_result()
      assert result["status"] == "ok"
      assert is_list(result["result"])
      assert length(result["result"]) >= 1
    end
  end

  describe "get_config" do
    test "returns current configuration" do
      result = Config.execute(%{action: "get_config"}, frame()) |> extract_result()
      assert result["status"] == "ok"
      r = result["result"]
      assert is_map(r["weights"])
      assert is_list(r["domains"])
      assert r["machines"] == 6
    end
  end

  describe "set_weights" do
    test "validates and sets dimension weights" do
      weights = Prism.Benchmark.CLCategories.default_weights()
      weights_json = weights |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end) |> Jason.encode!()

      result =
        Config.execute(%{action: "set_weights", weights: weights_json}, frame())
        |> extract_result()

      assert result["status"] == "ok"
      assert result["result"]["status"] == "updated"
    end

    test "returns error for missing weights" do
      result = Config.execute(%{action: "set_weights"}, frame()) |> extract_result()
      assert result["status"] == "error"
      assert result["error"] =~ "weights"
    end

    test "returns error for invalid dimension names" do
      weights_json = Jason.encode!(%{"nonexistent_dim" => 1.0})

      result =
        Config.execute(%{action: "set_weights", weights: weights_json}, frame())
        |> extract_result()

      assert result["status"] == "error"
    end
  end

  describe "create_profile" do
    test "creates a task profile with valid data" do
      priorities = Jason.encode!(%{"stability" => 0.8, "plasticity" => 0.5})
      domains = Jason.encode!(["code", "knowledge"])

      result =
        Config.execute(
          %{
            action: "create_profile",
            name: "test-profile",
            dimension_priorities: priorities,
            domains: domains
          },
          frame()
        )
        |> extract_result()

      assert result["status"] == "ok"
      r = result["result"]
      assert r["name"] == "test-profile"
      assert r["id"]
      assert r["dimension_priorities"]["stability"] == 0.8
      assert r["domains"] == ["code", "knowledge"]
    end

    test "returns error without required params" do
      result = Config.execute(%{action: "create_profile"}, frame()) |> extract_result()
      assert result["status"] == "error"
    end

    test "rejects invalid dimension names in priorities" do
      priorities = Jason.encode!(%{"fake_dimension" => 1.0})
      domains = Jason.encode!(["code"])

      result =
        Config.execute(
          %{action: "create_profile", name: "bad", dimension_priorities: priorities, domains: domains},
          frame()
        )
        |> extract_result()

      assert result["status"] == "error"
      assert result["error"] =~ "Invalid dimensions"
    end
  end
end
