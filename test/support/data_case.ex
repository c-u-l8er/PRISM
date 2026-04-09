defmodule Prism.DataCase do
  @moduledoc """
  Test case for tests requiring database access.

  Sets up the Ecto sandbox and runs migrations for the in-memory SQLite DB.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Prism.Repo
      import Ecto.Query
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Prism.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
