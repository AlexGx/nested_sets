defmodule NestedSets.Query do
  @moduledoc """
  Query builders for NestedSets.

  Provides composable query functions for traversing NestedSets trees.

  ## Examples

      # Get all ancestors of a node
      Category
      |> NestedSets.Query.ancestors(node)
      |> Repo.all()

      # Get direct children only
      Category
      |> NestedSets.Query.children(node, depth: 1)
      |> Repo.all()

      # Get all leaf nodes under a parent
      Category
      |> NestedSets.Query.leaves(parent)
      |> Repo.all()
  """

  import Ecto.Query

  defp config(schema), do: NestedSets.config(schema)

  defp get_schema(queryable) do
    case queryable do
      %Ecto.Query{from: %{source: {_, schema}}} -> schema
      schema when is_atom(schema) -> schema
    end
  end

  @doc """
  Finds all ancestors (parents) of a node.

  ## Options
    * `:depth` - limit to ancestors within N levels (optional)
  """
  @spec ancestors(Ecto.Queryable.t(), struct(), keyword()) :: Ecto.Query.t() | nil
  def ancestors(queryable, node, opts \\ []) do
    schema = get_schema(queryable)
    cfg = config(schema)
    depth_limit = Keyword.get(opts, :depth)

    node_lft = Map.get(node, cfg.lft)
    node_rgt = Map.get(node, cfg.rgt)
    node_depth = Map.get(node, cfg.depth)

    query =
      from(n in queryable,
        where: field(n, ^cfg.lft) < ^node_lft,
        where: field(n, ^cfg.rgt) > ^node_rgt,
        order_by: [asc: field(n, ^cfg.lft)]
      )

    query =
      if depth_limit do
        min_depth = node_depth - depth_limit

        from(n in query,
          where: field(n, ^cfg.depth) >= ^min_depth
        )
      else
        query
      end

    apply_tree_filter(query, node, cfg)
  end

  @doc """
  Alias for `ancestors/3`.
  """
  @spec parents(Ecto.Queryable.t(), struct(), keyword()) :: Ecto.Query.t() | nil
  def parents(queryable, node, opts \\ []), do: ancestors(queryable, node, opts)

  @doc """
  Finds all descendants (children) of a node.

  ## Options
    * `:depth` - limit to descendants within N levels (optional)
  """
  @spec descendants(Ecto.Queryable.t(), struct(), keyword()) :: Ecto.Query.t() | nil
  def descendants(queryable, node, opts \\ []) do
    schema = get_schema(queryable)
    cfg = config(schema)
    depth_limit = Keyword.get(opts, :depth)

    node_lft = Map.get(node, cfg.lft)
    node_rgt = Map.get(node, cfg.rgt)
    node_depth = Map.get(node, cfg.depth)

    query =
      from(n in queryable,
        where: field(n, ^cfg.lft) > ^node_lft,
        where: field(n, ^cfg.rgt) < ^node_rgt,
        order_by: [asc: field(n, ^cfg.lft)]
      )

    query =
      if depth_limit do
        max_depth = node_depth + depth_limit

        from(n in query,
          where: field(n, ^cfg.depth) <= ^max_depth
        )
      else
        query
      end

    apply_tree_filter(query, node, cfg)
  end

  @doc """
  Alias for `descendants/3`.
  """
  @spec children(Ecto.Queryable.t(), struct(), keyword()) :: Ecto.Query.t() | nil
  def children(queryable, node, opts \\ []), do: descendants(queryable, node, opts)

  @doc """
  Finds only direct children of a node (depth = 1).
  """
  @spec direct_children(Ecto.Queryable.t(), struct()) :: Ecto.Query.t() | nil
  def direct_children(queryable, node), do: descendants(queryable, node, depth: 1)

  @doc """
  Finds all leaf nodes (nodes without children) under a node.
  """
  @spec leaves(Ecto.Queryable.t(), struct()) :: Ecto.Query.t() | nil
  def leaves(queryable, node) do
    schema = get_schema(queryable)
    cfg = config(schema)

    node_lft = Map.get(node, cfg.lft)
    node_rgt = Map.get(node, cfg.rgt)

    query =
      from(n in queryable,
        where: field(n, ^cfg.lft) > ^node_lft,
        where: field(n, ^cfg.rgt) < ^node_rgt,
        where: field(n, ^cfg.rgt) == field(n, ^cfg.lft) + 1,
        order_by: [asc: field(n, ^cfg.lft)]
      )

    apply_tree_filter(query, node, cfg)
  end

  @doc """
  Finds the previous sibling of a node.
  """
  @spec prev_sibling(Ecto.Queryable.t(), struct()) :: Ecto.Query.t() | nil
  def prev_sibling(queryable, node) do
    schema = get_schema(queryable)
    cfg = config(schema)
    node_lft = Map.get(node, cfg.lft)

    query =
      from(n in queryable,
        where: field(n, ^cfg.rgt) == ^node_lft - 1,
        limit: 1
      )

    apply_tree_filter(query, node, cfg)
  end

  @doc """
  Alias for `prev_sibling/2`.
  """
  @spec prev(Ecto.Queryable.t(), struct()) :: Ecto.Query.t() | nil
  def prev(queryable, node), do: prev_sibling(queryable, node)

  @doc """
  Finds the next sibling of a node.
  """
  @spec next_sibling(Ecto.Queryable.t(), struct()) :: Ecto.Query.t() | nil
  def next_sibling(queryable, node) do
    schema = get_schema(queryable)
    cfg = config(schema)
    node_rgt = Map.get(node, cfg.rgt)

    query =
      from(n in queryable,
        where: field(n, ^cfg.lft) == ^node_rgt + 1,
        limit: 1
      )

    apply_tree_filter(query, node, cfg)
  end

  @doc """
  Alias for `next_sibling/2`.
  """
  @spec next(Ecto.Queryable.t(), struct()) :: Ecto.Query.t() | nil
  def next(queryable, node), do: next_sibling(queryable, node)

  @doc """
  Finds all siblings of a node (nodes with the same parent).
  """
  @spec siblings(Ecto.Queryable.t(), struct()) :: Ecto.Query.t() | nil
  def siblings(queryable, node) do
    schema = get_schema(queryable)
    cfg = config(schema)

    node_lft = Map.get(node, cfg.lft)
    node_rgt = Map.get(node, cfg.rgt)
    node_depth = Map.get(node, cfg.depth)
    pk = get_primary_key(node)

    parent_query =
      from(n in queryable,
        where: field(n, ^cfg.lft) < ^node_lft,
        where: field(n, ^cfg.rgt) > ^node_rgt,
        where: field(n, ^cfg.depth) == ^node_depth - 1,
        limit: 1
      )

    parent_query = apply_tree_filter(parent_query, node, cfg)

    from(n in queryable,
      where: n.id != ^pk,
      where: field(n, ^cfg.depth) == ^node_depth,
      where: field(n, ^cfg.lft) > subquery(from(p in parent_query, select: field(p, ^cfg.lft))),
      where: field(n, ^cfg.rgt) < subquery(from(p in parent_query, select: field(p, ^cfg.rgt))),
      order_by: [asc: field(n, ^cfg.lft)]
    )
    |> apply_tree_filter(node, cfg)
  end

  @doc """
  Finds all root nodes.
  """
  @spec roots(Ecto.Queryable.t()) :: Ecto.Query.t()
  def roots(queryable) do
    schema = get_schema(queryable)
    cfg = config(schema)

    from(n in queryable,
      where: field(n, ^cfg.lft) == 1,
      order_by: [asc: field(n, ^cfg.lft)]
    )
  end

  @doc """
  Finds the root node for a specific tree (when using tree).
  """
  @spec root(Ecto.Queryable.t(), struct()) :: Ecto.Query.t() | nil
  def root(queryable, node) do
    schema = get_schema(queryable)
    cfg = config(schema)

    query =
      from(n in queryable,
        where: field(n, ^cfg.lft) == 1,
        limit: 1
      )

    apply_tree_filter(query, node, cfg)
  end

  @doc """
  Gets a node and all its descendants (the full subtree including the node itself).
  """
  @spec subtree(Ecto.Queryable.t(), struct()) :: Ecto.Query.t() | nil
  def subtree(queryable, node) do
    schema = get_schema(queryable)
    cfg = config(schema)

    node_lft = Map.get(node, cfg.lft)
    node_rgt = Map.get(node, cfg.rgt)

    query =
      from(n in queryable,
        where: field(n, ^cfg.lft) >= ^node_lft,
        where: field(n, ^cfg.rgt) <= ^node_rgt,
        order_by: [asc: field(n, ^cfg.lft)]
      )

    apply_tree_filter(query, node, cfg)
  end

  @doc """
  Finds nodes at a specific depth level.
  """
  @spec at_depth(Ecto.Queryable.t(), integer()) :: Ecto.Query.t()
  def at_depth(queryable, depth) do
    schema = get_schema(queryable)
    cfg = config(schema)

    from(n in queryable,
      where: field(n, ^cfg.depth) == ^depth,
      order_by: [asc: field(n, ^cfg.lft)]
    )
  end

  @doc """
  @review: not only :integer
  Filters by a specific tree (when using tree).
  Accepts either a tree_id integer or a node struct.
  """
  @spec in_tree(Ecto.Queryable.t(), integer() | struct()) :: Ecto.Query.t() | nil
  def in_tree(queryable, tree_id) when is_integer(tree_id) do
    schema = get_schema(queryable)
    cfg = config(schema)

    if cfg.tree == false do
      queryable
    else
      from(n in queryable,
        where: field(n, ^cfg.tree) == ^tree_id
      )
    end
  end

  def in_tree(queryable, node) when is_struct(node) do
    schema = get_schema(queryable)
    cfg = config(schema)
    apply_tree_filter(queryable, node, cfg)
  end

  # Private section

  defp apply_tree_filter(query, _node, %{tree: false} = _cfg), do: query

  defp apply_tree_filter(query, node, %{tree: tree_attr} = _cfg) do
    tree_value = Map.get(node, tree_attr)
    from(n in query, where: field(n, ^tree_attr) == ^tree_value)
  end

  defp get_primary_key(node) do
    schema = node.__struct__
    [pk_field | _] = schema.__schema__(:primary_key)
    Map.get(node, pk_field)
  end
end
