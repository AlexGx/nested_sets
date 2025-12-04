defmodule NestedSets.Schema do
  @moduledoc """
  Macro for defining NestedSets fields in Ecto schema.

  ## Usage

      defmodule MyApp.Category do
        use Ecto.Schema
        use NestedSets.Schema,
          lft: :lft,
          rgt: :rgt,
          depth: :depth,
          tree: :tree

        schema "categories" do
          field :name, :string
          nested_sets_fields()
          timestamps()
        end
      end

  ## Options

    * `:lft` - the name of the left attribute (default: `:lft`)
    * `:rgt` - the name of the right attribute (default: `:rgt`)
    * `:depth` - the name of the depth attribute (default: `:depth`)
    * `:tree` - the name of the tree attribute or bool. If true -> attribute is defaulted to `:tree`, false for single tree mode. Default is `false`.

  ## Single vs multiple tree mode

  By default (`tree: false`), only one tree can exist in the table.
  Set `tree: true` or `tree: :tree_id` (or another field name) to support multiple
  independent trees in the same table.
  """

  defmacro __using__(opts \\ []) do
    lft = Keyword.get(opts, :lft, :lft)
    rgt = Keyword.get(opts, :rgt, :rgt)
    depth = Keyword.get(opts, :depth, :depth)

    tree =
      case Keyword.get(opts, :tree, false) do
        true -> :tree
        false -> false
        tree -> tree
      end

    quote do
      import NestedSets.Schema

      @__nested_sets_lft unquote(lft)
      @__nested_sets_rgt unquote(rgt)
      @__nested_sets_depth unquote(depth)
      @__nested_sets_tree unquote(tree)

      @doc false
      def __nested_sets_config__ do
        %{
          lft: @__nested_sets_lft,
          rgt: @__nested_sets_rgt,
          depth: @__nested_sets_depth,
          tree: @__nested_sets_tree
        }
      end
    end
  end

  @doc """
  Adds the NestedSets fields to the schema.

  This macro should be called inside the `schema` block.

  ## Example

      schema "categories" do
        field :name, :string
        nested_sets_fields()
      end
  """
  defmacro nested_sets_fields do
    quote do
      field @__nested_sets_lft, :integer
      field @__nested_sets_rgt, :integer
      field @__nested_sets_depth, :integer, default: 0

      if @__nested_sets_tree do
        field @__nested_sets_tree, :integer
      end
    end
  end
end
