defmodule NestedSets.MigrationTest do
  use NestedSets.Case, async: false

  alias Ecto.Adapters.SQL

  alias NestedSets.Test.Repos

  describe "nested_sets_fields/1" do
    for {db_type, repo, tags} <- Repos.list() do
      @describetag tags

      @tag db: db_type
      test "creates basic nested set fields without tree (#{db_type})" do
        repo = unquote(repo)
        db_type = unquote(db_type)
        table = unique_table_name()

        on_exit(fn -> drop_table(repo, table) end)

        create_table(repo, table, fn ->
          quote do
            NestedSets.Migration.nested_sets_fields()
          end
        end)

        columns = get_columns(repo, table)

        assert_column(columns, "lft", :integer, false, db_type)
        assert_column(columns, "rgt", :integer, false, db_type)
        assert_column(columns, "depth", :integer, false, db_type)
        refute_column(columns, "tree")
      end

      @tag db: db_type
      test "creates tree field with use_tree: true (#{db_type})" do
        repo = unquote(repo)
        db_type = unquote(db_type)
        table = unique_table_name()

        on_exit(fn -> drop_table(repo, table) end)

        create_table(repo, table, fn ->
          quote do
            NestedSets.Migration.nested_sets_fields(use_tree: true)
          end
        end)

        columns = get_columns(repo, table)

        assert_column(columns, "lft", :integer, false, db_type)
        assert_column(columns, "rgt", :integer, false, db_type)
        assert_column(columns, "depth", :integer, false, db_type)
        assert_column(columns, "tree", :integer, false, db_type)
      end

      @tag db: db_type
      test "creates custom named tree field with atom (#{db_type})" do
        repo = unquote(repo)
        db_type = unquote(db_type)
        table = unique_table_name()

        on_exit(fn -> drop_table(repo, table) end)

        create_table(repo, table, fn ->
          quote do
            NestedSets.Migration.nested_sets_fields(use_tree: :organization_id)
          end
        end)

        columns = get_columns(repo, table)

        assert_column(columns, "organization_id", :integer, false, db_type)
        refute_column(columns, "tree")
      end

      @tag db: db_type
      test "creates tree field with null: false (#{db_type})" do
        repo = unquote(repo)
        db_type = unquote(db_type)
        table = unique_table_name()

        on_exit(fn -> drop_table(repo, table) end)

        create_table(repo, table, fn ->
          quote do
            NestedSets.Migration.nested_sets_fields(use_tree: :tenant_id, tree_null: false)
          end
        end)

        columns = get_columns(repo, table)

        assert_column(columns, "tenant_id", :integer, false, db_type)
      end

      @tag db: db_type
      test "creates tree field with foreign key reference (#{db_type})" do
        repo = unquote(repo)
        db_type = unquote(db_type)
        ref_table = unique_table_name("orgs")
        table = unique_table_name()

        on_exit(fn ->
          drop_table(repo, table)
          drop_table(repo, ref_table)
        end)

        create_reference_table(repo, ref_table)

        create_table(repo, table, fn ->
          quote do
            NestedSets.Migration.nested_sets_fields(
              use_tree: :organization_id,
              tree_type: :id,
              tree_references: unquote(ref_table)
            )
          end
        end)

        columns = get_columns(repo, table)

        # SQLite uses integer for all integer types, others use bigint for references
        expected_type =
          case db_type do
            :sqlite -> :integer
            _non_sqlite -> :bigint
          end

        assert_column(columns, "organization_id", expected_type, false, db_type)

        fks = get_foreign_keys(repo, table, db_type)
        assert Enum.any?(fks, &(&1.column == "organization_id"))
      end

      @tag db: db_type
      test "use_tree: false does not create tree field (#{db_type})" do
        repo = unquote(repo)
        table = unique_table_name()

        on_exit(fn -> drop_table(repo, table) end)

        create_table(repo, table, fn ->
          quote do
            NestedSets.Migration.nested_sets_fields(use_tree: false)
          end
        end)

        columns = get_columns(repo, table)

        refute_column(columns, "tree")
      end

      @tag db: db_type
      test "use_tree: nil does not create tree field (#{db_type})" do
        repo = unquote(repo)
        table = unique_table_name()

        on_exit(fn -> drop_table(repo, table) end)

        create_table(repo, table, fn ->
          quote do
            NestedSets.Migration.nested_sets_fields(use_tree: nil)
          end
        end)

        columns = get_columns(repo, table)

        refute_column(columns, "tree")
      end
    end

    test "raises on invalid use_tree value" do
      defmodule InvalidMigrationTest do
        use Ecto.Migration
        require NestedSets.Migration

        def change do
          create table(:test_invalid) do
            NestedSets.Migration.nested_sets_fields(use_tree: 123)
          end
        end
      end

      assert_raise ArgumentError, ~r/`use_tree` must be bool or atom/, fn ->
        Ecto.Migrator.up(Repo, System.unique_integer([:positive]), InvalidMigrationTest,
          log: false
        )
      end
    end

    test "raises on missing tree_references when tree_type is :id" do
      defmodule MissingRefMigrationTest do
        use Ecto.Migration
        require NestedSets.Migration

        def change do
          create table(:test_missing_ref) do
            NestedSets.Migration.nested_sets_fields(use_tree: :org_id, tree_type: :id)
          end
        end
      end

      assert_raise KeyError, ~r/key :tree_references not found/, fn ->
        Ecto.Migrator.up(Repo, System.unique_integer([:positive]), MissingRefMigrationTest,
          log: false
        )
      end
    end
  end

  # Helper functions

  defp unique_table_name(prefix \\ "ns_test") do
    :"#{prefix}_#{System.unique_integer([:positive])}"
  end

  defp create_table(repo, table_name, fields_fn) do
    reset_migrations!(repo)

    fields_ast = fields_fn.()

    migration_module_name =
      String.to_atom("Elixir.NestedSets.TestMigration#{System.unique_integer([:positive])}")

    {:module, module, _, _} =
      Module.create(
        migration_module_name,
        quote do
          use Ecto.Migration
          # Add this line
          require NestedSets.Migration

          def change do
            create table(unquote(table_name)) do
              add :name, :string
              unquote(fields_ast)
            end
          end
        end,
        Macro.Env.location(__ENV__)
      )

    Ecto.Migrator.up(repo, System.unique_integer([:positive]), module, log: false)
  end

  defp create_reference_table(repo, table_name) do
    migration_module_name =
      String.to_atom("Elixir.NestedSets.RefMigration#{System.unique_integer([:positive])}")

    {:module, module, _, _} =
      Module.create(
        migration_module_name,
        quote do
          use Ecto.Migration

          def change do
            create table(unquote(table_name)) do
              add :name, :string
            end
          end
        end,
        Macro.Env.location(__ENV__)
      )

    Ecto.Migrator.up(repo, System.unique_integer([:positive]), module, log: false)
  end

  defp drop_table(repo, table_name) when is_atom(table_name) or is_binary(table_name) do
    case repo.__adapter__() do
      Ecto.Adapters.SQLite3 ->
        SQL.query(repo, "DROP TABLE IF EXISTS #{table_name}")

      _ ->
        SQL.query(repo, "DROP TABLE IF EXISTS #{table_name} CASCADE")
    end
  catch
    _, _ -> :ok
  end

  defp drop_table(_repo, _table_name), do: :ok

  defp get_columns(repo, table_name) do
    table_str = to_string(table_name)

    case repo.__adapter__() do
      Ecto.Adapters.SQLite3 ->
        # SQLite PRAGMA doesn't support parameterized queries
        case SQL.query(repo, "PRAGMA table_info(#{table_str})", []) do
          {:ok, %{rows: rows}} ->
            Enum.map(rows, &parse_column_row(&1, repo))

          _ ->
            []
        end

      _ ->
        query = column_query(repo)

        case SQL.query(repo, query, [table_str]) do
          {:ok, %{rows: rows}} ->
            Enum.map(rows, &parse_column_row(&1, repo))

          _ ->
            []
        end
    end
  end

  defp column_query(repo) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres ->
        """
        SELECT column_name, data_type, is_nullable
        FROM information_schema.columns
        WHERE table_name = $1
        """

      Ecto.Adapters.MyXQL ->
        """
        SELECT column_name, data_type, is_nullable
        FROM information_schema.columns
        WHERE table_name = ?
        AND table_schema = DATABASE()
        """
    end
  end

  defp parse_column_row(row, repo) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres ->
        [name, type, nullable] = row
        %{name: name, type: normalize_type(type, :postgres), nullable: nullable == "YES"}

      Ecto.Adapters.SQLite3 ->
        [_cid, name, type, notnull, _default, _pk] = row
        %{name: name, type: normalize_type(type, :sqlite), nullable: notnull == 0}

      Ecto.Adapters.MyXQL ->
        [name, type, nullable] = row
        %{name: name, type: normalize_type(type, :mysql), nullable: nullable == "YES"}
    end
  end

  defp normalize_type(type, :postgres) do
    case type do
      "integer" -> :integer
      "bigint" -> :bigint
      "character varying" -> :string
      "text" -> :string
      _ -> String.to_atom(type)
    end
  end

  defp normalize_type(type, :sqlite) do
    case String.downcase(type) do
      "integer" -> :integer
      "bigint" -> :bigint
      "text" -> :string
      "varchar" <> _ -> :string
      other -> String.to_atom(other)
    end
  end

  defp normalize_type(type, :mysql) do
    case String.downcase(type) do
      "int" -> :integer
      "bigint" -> :bigint
      "varchar" -> :string
      "text" -> :string
      other -> String.to_atom(other)
    end
  end

  defp get_foreign_keys(repo, table_name, db_type) do
    table_str = to_string(table_name)

    case db_type do
      :sqlite ->
        case SQL.query(repo, "PRAGMA foreign_key_list(#{table_str})", []) do
          {:ok, %{rows: rows}} -> Enum.map(rows, &parse_fk_row(&1, :sqlite))
          _ -> []
        end

      _ ->
        query = foreign_key_query(db_type)

        case SQL.query(repo, query, [table_str]) do
          {:ok, %{rows: rows}} -> Enum.map(rows, &parse_fk_row(&1, db_type))
          _ -> []
        end
    end
  end

  defp foreign_key_query(:postgres) do
    """
    SELECT
      kcu.column_name,
      ccu.table_name AS foreign_table_name,
      rc.delete_rule
    FROM information_schema.table_constraints AS tc
    JOIN information_schema.key_column_usage AS kcu
      ON tc.constraint_name = kcu.constraint_name
    JOIN information_schema.constraint_column_usage AS ccu
      ON ccu.constraint_name = tc.constraint_name
    JOIN information_schema.referential_constraints AS rc
      ON rc.constraint_name = tc.constraint_name
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_name = $1
    """
  end

  defp foreign_key_query(:mysql) do
    """
    SELECT
      kcu.column_name,
      kcu.referenced_table_name,
      rc.delete_rule
    FROM information_schema.key_column_usage kcu
    JOIN information_schema.referential_constraints rc
      ON kcu.constraint_name = rc.constraint_name
      AND kcu.constraint_schema = rc.constraint_schema
    WHERE kcu.table_name = ?
      AND kcu.table_schema = DATABASE()
      AND kcu.referenced_table_name IS NOT NULL
    """
  end

  defp parse_fk_row(row, :postgres) do
    [column, foreign_table, delete_rule] = row
    %{column: column, foreign_table: foreign_table, delete_rule: delete_rule}
  end

  defp parse_fk_row(row, :sqlite) do
    [_id, _seq, foreign_table, column, _to, _on_update, delete_rule, _match] = row
    %{column: column, foreign_table: foreign_table, delete_rule: delete_rule}
  end

  defp parse_fk_row(row, :mysql) do
    [column, foreign_table, delete_rule] = row
    %{column: column, foreign_table: foreign_table, delete_rule: delete_rule}
  end

  defp assert_column(columns, name, expected_type, expected_nullable, db_type) do
    column = Enum.find(columns, &(&1.name == name))

    assert column != nil,
           "Expected column '#{name}' to exist in #{db_type}. Found: #{inspect(Enum.map(columns, & &1.name))}"

    assert column.type == expected_type,
           "Expected column '#{name}' to have type #{inspect(expected_type)}, got #{inspect(column.type)} (#{db_type})"

    assert column.nullable == expected_nullable,
           "Expected column '#{name}' nullable=#{expected_nullable}, got #{column.nullable} (#{db_type})"
  end

  defp refute_column(columns, name) do
    column = Enum.find(columns, &(&1.name == name))
    assert column == nil, "Expected column '#{name}' to NOT exist, but found it"
  end

  defp reset_migrations!(repo) do
    migration_table = repo.config()[:migration_source] || "schema_migrations"
    repo.query!("DELETE FROM #{migration_table}")
  end
end
