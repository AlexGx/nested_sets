defmodule NestedSets.Helpers do
  @moduledoc """
  Helper functions for NestedSets trees.

  Provides utility functions for tree traversal, conversion, and analysis.
  """

  @type ns_node :: struct()

  @doc """
  Builds a nested tree structure from a flat list of nodes.

  Returns a list of root nodes with a `:children` key containing nested children.
  Nodes must be sorted by `lft` before calling this function.

  ## Options
    * `:child_key` - the key to use for children (default: `:children`)

  ## Example

      nodes = Repo.all(from n in Category, order_by: n.lft)
      tree = NestedSets.Helpers.build_tree(nodes, Category)
  """
  @spec build_tree([ns_node()], module(), keyword()) :: [map()]
  def build_tree(nodes, schema, opts \\ []) do
    cfg = NestedSets.config(schema)
    child_key = Keyword.get(opts, :child_key, :children)

    nodes
    |> Enum.sort_by(&Map.get(&1, cfg.lft))
    |> do_build_tree(cfg, child_key, [])
    |> Enum.reverse()
  end

  defp do_build_tree([], _cfg, _child_key, acc), do: acc

  defp do_build_tree([node | rest], cfg, child_key, acc) do
    node_rgt = Map.get(node, cfg.rgt)

    {children_nodes, remaining} =
      Enum.split_while(rest, fn n ->
        Map.get(n, cfg.rgt) < node_rgt
      end)

    children = do_build_tree(children_nodes, cfg, child_key, []) |> Enum.reverse()
    node_with_children = Map.put(node, child_key, children)

    do_build_tree(remaining, cfg, child_key, [node_with_children | acc])
  end

  @doc """
  Converts a nested tree structure to a flat list with depth indication.

  ## Example

      flat_list = NestedSets.Helpers.flatten_tree(tree)
      # Returns [{node, 0}, {child, 1}, {grandchild, 2}, ...]
  """
  @spec flatten_tree([ns_node()], keyword()) :: [{map(), integer()}]
  def flatten_tree(tree, opts \\ []) do
    child_key = Keyword.get(opts, :child_key, :children)
    do_flatten_tree(tree, child_key, 0, []) |> Enum.reverse()
  end

  defp do_flatten_tree([], _child_key, _depth, acc), do: acc

  defp do_flatten_tree([node | rest], child_key, depth, acc) do
    children = Map.get(node, child_key, [])
    node_without_children = Map.delete(node, child_key)

    acc = [{node_without_children, depth} | acc]
    acc = do_flatten_tree(children, child_key, depth + 1, acc)
    do_flatten_tree(rest, child_key, depth, acc)
  end

  @doc """
  Returns the path from root to the given node as a string.

  ## Options
    * `:separator` - the separator between node names (default: `" > "`)
    * `:name_field` - the field to use for node names (default: `:name`)

  ## Example

      path = NestedSets.Helpers.path_string(node, ancestors, separator: " / ")
      # "Root / Parent / Child"
  """
  @spec path_string(ns_node(), [ns_node()], keyword()) :: String.t()
  def path_string(node, ancestors, opts \\ []) do
    separator = Keyword.get(opts, :separator, " > ")
    name_field = Keyword.get(opts, :name_field, :name)

    nodes = ancestors ++ [node]

    nodes
    |> Enum.map_join(separator, &Map.get(&1, name_field))
  end

  @doc """
  Generates indentation for displaying tree nodes.

  ## Options
    * `:indent_string` - the string to use for each level (default: `"  "`)
    * `:prefix` - optional prefix for non-root nodes (default: `""`)

  ## Example

      indent = NestedSets.Helpers.indent(node, "├── ")
  """
  @spec indent(ns_node(), keyword()) :: String.t()
  def indent(node, opts \\ []) do
    cfg = NestedSets.config(node)
    indent_string = Keyword.get(opts, :indent_string, "  ")
    prefix = Keyword.get(opts, :prefix, "")

    depth = Map.get(node, cfg.depth)

    if depth == 0 do
      ""
    else
      String.duplicate(indent_string, depth) <> prefix
    end
  end

  @doc """
  Validates the integrity of a NestedSets tree.

  Returns `:ok` if the tree is valid, or `{:error, reason}` with details.

  ## Checks performed:
    * Left values are less than right values
    * No overlapping ranges
    * Depth values are consistent
  """
  @spec validate_tree([ns_node()], module()) :: :ok | {:error, term()}
  def validate_tree(nodes, schema) do
    cfg = NestedSets.config(schema)

    with :ok <- validate_lft_rgt_order(nodes, cfg),
         :ok <- validate_no_overlaps(nodes, cfg) do
      validate_depths(nodes, cfg)
    end
  end

  defp validate_lft_rgt_order(nodes, cfg) do
    invalid =
      Enum.find(nodes, fn node ->
        Map.get(node, cfg.lft) >= Map.get(node, cfg.rgt)
      end)

    if invalid do
      {:error, {:invalid_lft_rgt, invalid}}
    else
      :ok
    end
  end

  defp validate_no_overlaps(nodes, cfg) do
    sorted = Enum.sort_by(nodes, &Map.get(&1, cfg.lft))

    result =
      sorted
      |> Enum.reduce_while({[], []}, fn node, {stack, _errors} ->
        lft = Map.get(node, cfg.lft)
        rgt = Map.get(node, cfg.rgt)

        stack = Enum.drop_while(stack, fn {_n, r} -> r < lft end)

        case stack do
          [{_parent, parent_rgt} | _] when rgt > parent_rgt ->
            {:halt, {:error, {:overlap, node}}}

          _ ->
            {:cont, {[{node, rgt} | stack], []}}
        end
      end)

    case result do
      {:error, _} = err -> err
      _ -> :ok
    end
  end

  defp validate_depths(nodes, cfg) do
    sorted = Enum.sort_by(nodes, &Map.get(&1, cfg.lft))

    result =
      sorted
      |> Enum.reduce_while({[], :ok}, fn node, {stack, _status} ->
        lft = Map.get(node, cfg.lft)
        rgt = Map.get(node, cfg.rgt)
        depth = Map.get(node, cfg.depth)

        stack = Enum.drop_while(stack, fn {_n, r, _d} -> r < lft end)

        expected_depth = length(stack)

        if depth != expected_depth do
          {:halt, {stack, {:error, {:invalid_depth, node, expected_depth}}}}
        else
          {:cont, {[{node, rgt, depth} | stack], :ok}}
        end
      end)

    case result do
      {_, :ok} -> :ok
      {_, {:error, _} = err} -> err
    end
  end

  @doc """
  Rebuilds nested sets values from a hierarchical structure.

  Returns a list of tuples `{node_data, lft, rgt, depth}` that can be used
  to populate the database.

  ## Example

      data = [
        %{name: "Root", children: [
          %{name: "Child 1", children: []},
          %{name: "Child 2", children: [
            %{name: "Grandchild", children: []}
          ]}
        ]}
      ]

      nodes = NestedSets.Helpers.rebuild_from_hierarchy(data)
      # [{%{name: "Root"}, 1, 8, 0}, {%{name: "Child 1"}, 2, 3, 1}, ...]
  """
  @spec rebuild_from_hierarchy([map()], keyword()) :: [{map(), integer(), integer(), integer()}]
  def rebuild_from_hierarchy(data, opts \\ []) do
    child_key = Keyword.get(opts, :child_key, :children)
    {nodes, _counter} = do_rebuild(data, child_key, 0, 1, [])
    Enum.reverse(nodes)
  end

  defp do_rebuild([], _child_key, _depth, counter, acc) do
    {acc, counter}
  end

  defp do_rebuild([node | rest], child_key, depth, counter, acc) do
    lft = counter
    children = Map.get(node, child_key, [])
    node_without_children = Map.delete(node, child_key)

    {acc, counter} =
      if Enum.empty?(children) do
        rgt = counter + 1
        {[{node_without_children, lft, rgt, depth} | acc], counter + 2}
      else
        {child_acc, new_counter} =
          do_rebuild(children, child_key, depth + 1, counter + 1, acc)

        rgt = new_counter
        {[{node_without_children, lft, rgt, depth} | child_acc], new_counter + 1}
      end

    do_rebuild(rest, child_key, depth, counter, acc)
  end
end
