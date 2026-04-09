defmodule Prism.System do
  @moduledoc """
  Ecto schema for registered memory systems.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "prism_systems" do
    field(:name, :string)
    field(:display_name, :string)
    field(:mcp_endpoint, :string)
    field(:transport, :string)
    field(:version, :string)
    field(:tool_count, :integer)
    field(:capabilities, :map)

    field(:registered_at, :utc_datetime_usec, default: nil)
    field(:last_seen_at, :utc_datetime_usec)
  end

  def changeset(system, attrs) do
    system
    |> cast(attrs, [
      :name,
      :display_name,
      :mcp_endpoint,
      :transport,
      :version,
      :tool_count,
      :capabilities
    ])
    |> validate_required([:name, :display_name, :mcp_endpoint, :transport])
    |> validate_inclusion(:transport, ~w(stdio sse))
    |> unique_constraint(:name)
  end
end
