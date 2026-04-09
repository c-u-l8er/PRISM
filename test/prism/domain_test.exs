defmodule Prism.DomainTest do
  use ExUnit.Case, async: true

  alias Prism.Domain

  describe "all/0" do
    test "returns 8 domains" do
      assert length(Domain.all()) == 8
    end

    test "returns atoms" do
      assert Enum.all?(Domain.all(), &is_atom/1)
    end
  end

  describe "validate/1" do
    test "accepts valid atom domains" do
      for domain <- Domain.all() do
        assert {:ok, ^domain} = Domain.validate(domain)
      end
    end

    test "accepts valid string domains" do
      for domain <- Domain.all_strings() do
        assert {:ok, _atom} = Domain.validate(domain)
      end
    end

    test "rejects invalid domains" do
      assert {:error, _} = Domain.validate(:invalid)
      assert {:error, _} = Domain.validate("nope")
    end
  end

  describe "all_strings/0" do
    test "returns string versions" do
      strings = Domain.all_strings()
      assert "code" in strings
      assert "medical" in strings
      assert length(strings) == 8
    end
  end

  describe "label/1" do
    test "returns human-readable labels" do
      assert Domain.label(:code) == "Code"
      assert Domain.label(:medical) == "Medical"
    end

    test "returns nil for invalid domains" do
      assert Domain.label(:bogus) == nil
    end
  end

  describe "validate_focus/1" do
    test "accepts valid focus list" do
      assert {:ok, [:code, :medical]} = Domain.validate_focus([:code, :medical])
    end

    test "accepts empty list" do
      assert {:ok, []} = Domain.validate_focus([])
    end

    test "rejects list with invalid domains" do
      assert {:error, _} = Domain.validate_focus([:code, :bogus])
    end
  end
end
