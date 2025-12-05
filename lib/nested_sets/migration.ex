defmodule NestedSets.Migration do
  @moduledoc """
  Migration helpers for NestedSets.

  ## Usage

  In your migration:

      defmodule MyApp.Repo.Migrations.CreateCategories do
        use Ecto.Migration
        import NestedSets.Migration

        def change do
          create table(:categories) do
            add :name, :string, null: false
            nested_sets_columns()
            # or with custom options:
            # nested_sets_columns(tree: :group_id)
            timestamps()
          end

          # Add indexes based on your NestedSets usage strategy (for ex. `lft` as index, composite index [`name`, `tree`] in multi mode)
        end
      end
  """

  use Ecto.Migration

  defmacro nested_sets_columns(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      add :lft, :integer, null: false
      add :rgt, :integer, null: false
      add :depth, :integer, null: false, default: 0

      use_tree = Keyword.get(opts, :use_tree, false)

      tree_field =
        case use_tree do
          true ->
            :tree

          false ->
            nil

          atom when is_atom(atom) ->
            atom

          other ->
            raise ArgumentError,
                  "`use_tree` must be bool or atom, got: #{inspect(other)}"
        end

      if tree_field do
        tree_type = Keyword.get(opts, :tree_type, :integer)

        on_tree_delete = Keyword.get(opts, :on_tree_delete, :delete_all)

        case tree_type do
          :integer ->
            add tree_field, tree_type, null: false, default: 0

          :id ->
            tree_ref = Keyword.fetch!(opts, :tree_references)
            add tree_field, references(tree_ref, on_delete: on_tree_delete), null: false
        end
      end
    end
  end
end
