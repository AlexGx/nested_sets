defmodule NestedSets.Case do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL

  alias NestedSets.Test.{
    Repo,
    # MysqlRepo,
    SqliteRepo
  }

  using do
    quote do
      alias NestedSets.Test.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import NestedSets.Case
    end
  end

  setup context do
    shared = not context[:async]

    # always setup PostgreSQL sandbox (for NestedSets storage)
    pg_pid = SQL.Sandbox.start_owner!(Repo, shared: shared)
    on_exit(fn -> SQL.Sandbox.stop_owner(pg_pid) end)

    # if test needs SQLite, set up SQLite sandbox too
    if context[:sqlite] do
      sqlite_pid = SQL.Sandbox.start_owner!(SqliteRepo, shared: shared)
      on_exit(fn -> SQL.Sandbox.stop_owner(sqlite_pid) end)
    end

    # if test needs MySQL, set up MySQL sandbox too
    # if context[:mysql] do
    #   mysql_pid = SQL.Sandbox.start_owner!(MysqlRepo, shared: shared)
    #   on_exit(fn -> SQL.Sandbox.stop_owner(mysql_pid) end)
    # end

    :ok
  end

  @doc """
  Transforms changeset errors into a map of messages for easy assertions.
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
