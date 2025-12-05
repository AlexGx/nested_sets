defmodule NestedSets do
  @moduledoc """
  NestedSets for Ecto with multi tree support.

  ## Usage

  1. Create a migration:

      ```elixir
      defmodule MyApp.Repo.Migrations.CreateCategories do
        use Ecto.Migration
        import NestedSets.Migration

        def change do
          create table(:categories) do
            add :name, :string, null: false
            nested_sets_columns(tree: :tree_id)
            timestamps()
          end

          nested_sets_indexes(:categories, tree: :tree_id)
        end
      end
      ```

  2. Define your schema:

      ```elixir
      defmodule MyApp.Category do
        use Ecto.Schema
        use NestedSets.Schema,
          lft: :lft,
          rgt: :rgt,
          depth: :depth,
          tree: :tree_id

        schema "categories" do
          field :name, :string
          nested_sets_fields()
          timestamps()
        end
      end
      ```

  3. Use tree operations:

      ```elixir
      alias MyApp.{Repo, Category}

      # Create root
      {:ok, root} = NestedSets.make_root(Repo, %Category{name: "Root"})

      # Append child
      {:ok, child} = NestedSets.append_to(Repo, %Category{name: "Child"}, root)

      # Query descendants
      Category |> NestedSets.Query.descendants(parent) |> Repo.all()
      ```
  """

  import Ecto.Query

  @type ns_node :: struct()
  @type error_reason :: String.t() | Ecto.Changeset.t() | term()
  @type operation_result :: {:ok, ns_node()} | {:error, error_reason()}
  @type depth :: non_neg_integer() | nil
  @type delete_result :: {:ok, non_neg_integer()} | {:error, error_reason()}

  @typep position :: :prepend | :append | :before | :after
  @typep validation_result :: :ok | {:error, String.t()}

  @doc false
  def config(node) when is_struct(node), do: config(node.__struct__)

  def config(schema) when is_atom(schema) do
    if function_exported?(schema, :__nested_sets_config__, 0) do
      schema.__nested_sets_config__()
    else
      raise ArgumentError,
            "Schema #{inspect(schema)} does not use NestedSets.Schema. " <>
              "Add `use NestedSets.Schema` to your schema module."
    end
  end

  @doc """
  Creates a new root node.

  If `tree` is false, only one root can exist.
  If `tree` is configured, the tree id will be set to the node's primary key after insert.

  ## Examples

      {:ok, root} = NestedSets.make_root(Repo, %Category{name: "Root"})
  """
  @spec make_root(Ecto.Repo.t(), ns_node()) ::
          {:ok, ns_node()} | {:error, term() | Ecto.Changeset.t()}
  def make_root(repo, node) do
    cfg = config(node)

    repo.transact(fn ->
      with :ok <- validate_single_root(repo, node, cfg),
           {:ok, inserted} <- insert_root_node(repo, node, cfg) do
        {:ok, maybe_set_tree_id(repo, inserted, cfg)}
      end
    end)
  end

  defp validate_single_root(_repo, _node, %{tree: tree}) when tree != false, do: :ok

  defp validate_single_root(repo, node, cfg) do
    exists? = repo.exists?(from n in node.__struct__, where: field(n, ^cfg.lft) == 1)
    if exists?, do: {:error, :root_already_exists}, else: :ok
  end

  defp insert_root_node(repo, node, cfg) do
    node
    |> Ecto.Changeset.change(%{cfg.lft => 1, cfg.rgt => 2, cfg.depth => 0})
    |> repo.insert()
  end

  defp maybe_set_tree_id(_repo, node, %{tree: false}), do: node

  defp maybe_set_tree_id(repo, node, cfg) do
    pk = get_primary_key(node)

    {1, _} =
      repo.update_all(
        from(n in node.__struct__, where: n.id == ^pk),
        set: [{cfg.tree, pk}]
      )

    repo.get!(node.__struct__, pk)
  end

  @doc """
  Creates a node as the first child of the target node, or moves an existing node.

  ## Examples

      {:ok, child} = NestedSets.prepend_to(Repo, %Category{name: "First Child"}, parent)
  """

  @spec prepend_to(Ecto.Repo.t(), ns_node(), ns_node()) :: operation_result()
  def prepend_to(repo, node, target), do: save_node(repo, node, target, :prepend)

  @doc """
  Creates a node as the last child of the target node, or moves an existing node.

  ## Examples

      {:ok, child} = NestedSets.append_to(Repo, %Category{name: "Last Child"}, parent)
  """
  @spec append_to(Ecto.Repo.t(), ns_node(), ns_node()) :: {:ok, ns_node()} | {:error, term()}
  def append_to(repo, node, target) do
    save_node(repo, node, target, :append)
  end

  @doc """
  Creates a node as the previous sibling of the target node, or moves an existing node.

  ## Examples

      {:ok, sibling} = NestedSets.insert_before(Repo, %Category{name: "Before"}, target)
  """
  @spec insert_before(Ecto.Repo.t(), ns_node(), ns_node()) :: {:ok, ns_node()} | {:error, term()}
  def insert_before(repo, node, target), do: save_node(repo, node, target, :before)

  @doc """
  Creates a node as the next sibling of the target node, or moves an existing node.

  ## Examples

      {:ok, sibling} = NestedSets.insert_after(Repo, %Category{name: "After"}, target)
  """
  @spec insert_after(Ecto.Repo.t(), ns_node(), ns_node()) :: {:ok, ns_node()} | {:error, term()}
  def insert_after(repo, node, target), do: save_node(repo, node, target, :after)

  @doc """
  Deletes a node and all its children.

  ## Examples

      {:ok, count} = NestedSets.delete_with_children(Repo, node)
  """

  @spec delete_with_children(Ecto.Repo.t(), ns_node()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def delete_with_children(repo, node) do
    cfg = config(node)

    repo.transact(fn ->
      refreshed = repo.reload!(node)
      lft = Map.get(refreshed, cfg.lft)
      rgt = Map.get(refreshed, cfg.rgt)
      width = rgt - lft + 1

      query =
        from(n in node.__struct__,
          where: field(n, ^cfg.lft) >= ^lft,
          where: field(n, ^cfg.rgt) <= ^rgt
        )
        |> apply_tree_condition(refreshed, cfg)

      {count, _} = repo.delete_all(query)

      # close the gap
      shift_left_right(repo, refreshed, rgt + 1, -width, cfg)

      {:ok, count}
    end)
  end

  @doc """
  Deletes a single node, promoting its children up one level.

  ## Examples

      {:ok, node} = NestedSets.delete_node(Repo, node)
  """
  @spec delete_node(Ecto.Repo.t(), ns_node()) :: {:ok, ns_node()} | {:error, term()}
  def delete_node(repo, node) do
    # @review: root node deletion
    if root?(node) do
      {:error, :cannot_delete_root}
    else
      do_delete_node(repo, node)
    end
  end

  defp do_delete_node(repo, node) do
    cfg = config(node)

    repo.transact(fn ->
      refreshed = repo.reload!(node)
      lft = Map.get(refreshed, cfg.lft)
      rgt = Map.get(refreshed, cfg.rgt)

      deleted = repo.delete!(refreshed)

      # if it has children, shift them up/left to fill the parent's shell
      if rgt - lft > 1 do
        query =
          from(n in node.__struct__,
            where: field(n, ^cfg.lft) > ^lft and field(n, ^cfg.rgt) < ^rgt
          )
          |> apply_tree_condition(refreshed, cfg)

        repo.update_all(query,
          inc: [
            {cfg.lft, -1},
            {cfg.rgt, -1},
            {cfg.depth, -1}
          ]
        )
      end

      # close the gap (width of 2 for the single node deleted)
      shift_left_right(repo, refreshed, rgt + 1, -2, cfg)

      {:ok, deleted}
    end)
  end

  @doc """
  Moves an existing node to become a new root (only valid with tree).

  ## Examples

      {:ok, new_root} = NestedSets.make_root_from(Repo, existing_node)
  """
  @spec make_root_from(Ecto.Repo.t(), ns_node()) :: {:ok, ns_node()} | {:error, term()}
  def make_root_from(repo, node) do
    cfg = config(node)

    cond do
      cfg.tree == false ->
        {:error, :tree_required}

      root?(node) ->
        {:error, :already_root}

      true ->
        move_node_as_root(repo, node, cfg)
    end
  end

  # Predicates

  @doc """
  Checks a node is a root.
  """
  @spec root?(ns_node()) :: boolean()
  def root?(node) do
    cfg = config(node)
    Map.get(node, cfg.lft) == 1
  end

  @doc """
  Checks if a node is a leaf node (has no children).
  """
  @spec leaf?(ns_node()) :: boolean()
  def leaf?(node) do
    cfg = config(node)
    Map.get(node, cfg.rgt) - Map.get(node, cfg.lft) == 1
  end

  @doc """
  Checks if node is a child/descendant of the potential parent.
  """
  @spec descendant_of?(ns_node(), ns_node()) :: boolean()
  def descendant_of?(node, potential_parent) do
    if node.__struct__ != potential_parent.__struct__ do
      raise ArgumentError,
            "descendant_of?/2 expects both arguments to be structs of the same Schema, " <>
              "got #{inspect(node.__struct__)} and #{inspect(potential_parent.__struct__)}"
    end

    cfg = config(node)

    node_lft = Map.get(node, cfg.lft)
    node_rgt = Map.get(node, cfg.rgt)
    parent_lft = Map.get(potential_parent, cfg.lft)
    parent_rgt = Map.get(potential_parent, cfg.rgt)

    descendant? = node_lft > parent_lft && node_rgt < parent_rgt

    if descendant? && cfg.tree != false do
      Map.get(node, cfg.tree) == Map.get(potential_parent, cfg.tree)
    else
      descendant?
    end
  end

  @doc """
  Checks if node is a direct child of the potential parent.
  """
  @spec child_of?(ns_node(), ns_node()) :: boolean()
  def child_of?(node, potential_parent) do
    if node.__struct__ != potential_parent.__struct__ do
      raise ArgumentError,
            "child_of?/2 expects both arguments to be structs of the same Schema, " <>
              "got #{inspect(node.__struct__)} and #{inspect(potential_parent.__struct__)}"
    end

    cfg = config(node)

    same_scope? =
      if cfg.tree != false do
        Map.get(node, cfg.tree) == Map.get(potential_parent, cfg.tree)
      else
        true
      end

    node_lft = Map.get(node, cfg.lft)
    node_rgt = Map.get(node, cfg.rgt)
    parent_lft = Map.get(potential_parent, cfg.lft)
    parent_rgt = Map.get(potential_parent, cfg.rgt)

    descendant? = node_lft > parent_lft && node_rgt < parent_rgt

    correct_depth? = Map.get(node, cfg.depth) == Map.get(potential_parent, cfg.depth) + 1

    same_scope? && descendant? && correct_depth?
  end

  @doc """
  Returns the number of descendants for a node.
  """
  @spec descendant_count(ns_node()) :: non_neg_integer()
  def descendant_count(node) do
    cfg = config(node)
    rgt = Map.get(node, cfg.rgt)
    lft = Map.get(node, cfg.lft)
    div(rgt - lft - 1, 2)
  end

  # Private section

  @spec loaded?(ns_node()) :: boolean()
  defp loaded?(%{__meta__: %{state: :loaded}}), do: true
  defp loaded?(_), do: false

  @spec save_node(Ecto.Repo.t(), ns_node(), ns_node(), position()) :: operation_result()
  defp save_node(repo, node, target, position) do
    case loaded?(node) do
      true -> move_node(repo, node, target, position)
      false -> insert_node(repo, node, target, position)
    end
  end

  @spec insert_node(Ecto.Repo.t(), ns_node(), ns_node(), position()) :: operation_result()
  defp insert_node(repo, node, target, position) do
    cfg = config(node)

    if node.__struct__ != target.__struct__ do
      raise ArgumentError,
            "insert_node/4 expects both arguments to be structs of the same Schema, " <>
              "got #{inspect(node.__struct__)} and #{inspect(target.__struct__)}"
    end

    repo.transact(fn ->
      target = repo.reload!(target)

      with {:ok, value, depth} <- calculate_insert_position(target, position),
           :ok <- validate_insert(target, position),
           :ok <- shift_left_right(repo, target, value, 2, cfg) do
        attrs =
          %{
            cfg.lft => value,
            cfg.rgt => value + 1,
            cfg.depth => Map.get(target, cfg.depth) + depth
          }
          |> maybe_put_tree(target, cfg)

        node = Ecto.Changeset.change(node, attrs) |> repo.insert!()

        {:ok, node}
      end
    end)
  end

  @spec validate_insert(ns_node(), position()) :: validation_result()
  defp validate_insert(target, position) do
    cond do
      not loaded?(target) ->
        {:error, "cannot insert when target node is new."}

      position in [:before, :after] && root?(target) ->
        {:error, "cannot insert before or after root node."}

      true ->
        :ok
    end
  end

  @spec move_node(Ecto.Repo.t(), ns_node(), ns_node(), position()) :: operation_result()
  defp move_node(repo, node, target, position) do
    if node.__struct__ != target.__struct__ do
      raise ArgumentError,
            "move_node/4 expects both arguments to be structs of the same Schema, " <>
              "got #{inspect(node.__struct__)} and #{inspect(target.__struct__)}"
    end

    repo.transact(fn ->
      # lock and reload! to ensure we have the absolute latest tree state
      node = repo.reload!(node)
      target = repo.reload!(target)

      with :ok <- validate_move(node, target, position) do
        do_move_node(repo, node, target, position)
      end
    end)
  end

  @spec do_move_node(Ecto.Repo.t(), ns_node(), ns_node(), position()) :: {:ok, ns_node()}
  defp do_move_node(repo, node, target, position) do
    cfg = config(node)

    same_tree? =
      cfg.tree == false ||
        Map.get(node, cfg.tree) == Map.get(target, cfg.tree)

    # we are crossing trees (if multi-tree is enabled) ?
    if same_tree? do
      move_within_tree(repo, node, target, position, cfg)
    else
      move_between_trees(repo, node, target, position, cfg)
    end

    {:ok, repo.reload!(node)}
  end

  defp move_within_tree(repo, node, target, position, cfg) do
    node_lft = Map.get(node, cfg.lft)
    node_rgt = Map.get(node, cfg.rgt)
    width = node_rgt - node_lft + 1

    # calculate destination
    {dest_lft, new_depth} = calculate_destination(node, target, position, cfg)

    # make space (Shift everything >= dest_lft)
    shift_left_right(repo, node, dest_lft, width, cfg)

    # adjust context coordinates if they shifted
    # if the node was to the right of destination, it moved right
    {current_lft, current_rgt} =
      if node_lft >= dest_lft do
        {node_lft + width, node_rgt + width}
      else
        {node_lft, node_rgt}
      end

    # move the subtree
    depth_diff = new_depth - Map.get(node, cfg.depth)
    move_distance = dest_lft - current_lft

    subtree_query =
      from(n in node.__struct__,
        where: field(n, ^cfg.lft) >= ^current_lft,
        where: field(n, ^cfg.rgt) <= ^current_rgt
      )

    subtree_query = apply_tree_condition(subtree_query, node, cfg)

    # optimization: update depth, lft, and rgt in one query
    repo.update_all(subtree_query,
      inc: [
        {cfg.depth, depth_diff},
        {cfg.lft, move_distance},
        {cfg.rgt, move_distance}
      ]
    )

    # close the original gap
    shift_left_right(repo, node, current_rgt + 1, -width, cfg)
  end

  defp move_between_trees(repo, node, target, position, cfg) do
    node_lft = Map.get(node, cfg.lft)
    node_rgt = Map.get(node, cfg.rgt)
    width = node_rgt - node_lft + 1

    target_tree_id = Map.get(target, cfg.tree)

    # calculate destination in target tree
    {dest_lft, new_depth} = calculate_destination(node, target, position, cfg)

    # make space in target tree (using target for context)
    shift_left_right(repo, target, dest_lft, width, cfg)

    # move subtree from source to target
    lft_diff = dest_lft - node_lft
    depth_diff = new_depth - Map.get(node, cfg.depth)

    subtree_query =
      from(n in node.__struct__,
        where: field(n, ^cfg.lft) >= ^node_lft,
        where: field(n, ^cfg.rgt) <= ^node_rgt
      )

    # important: apply condition using Source node (old tree id)
    subtree_query = apply_tree_condition(subtree_query, node, cfg)

    repo.update_all(subtree_query,
      inc: [
        {cfg.lft, lft_diff},
        {cfg.rgt, lft_diff},
        {cfg.depth, depth_diff}
      ],
      set: [{cfg.tree, target_tree_id}]
    )

    # close gap in source tree (using node for context)
    # subtree is logically gone from source -> close the gap at node_rgt
    shift_left_right(repo, node, node_rgt + 1, -width, cfg)
  end

  # calc the target left ID and depth based on position logic
  defp calculate_destination(_node, target, position, cfg) do
    target_lft = Map.get(target, cfg.lft)
    target_rgt = Map.get(target, cfg.rgt)
    target_depth = Map.get(target, cfg.depth)

    case position do
      :prepend ->
        # becomes the first child
        {target_lft + 1, target_depth + 1}

      :append ->
        # becomes the last child
        # insert at target_rgt. The existing target_rgt moves right to accommodate.
        {target_rgt, target_depth + 1}

      :before ->
        # same depth, takes target's left position
        {target_lft, target_depth}

      :after ->
        # same depth, takes position after target
        {target_rgt + 1, target_depth}
    end
  end

  # shifts everything >= start_val by delta
  defp shift_left_right(repo, context_node, start_val, delta, cfg) do
    schema = context_node.__struct__

    # must be two separate updates because the WHERE clause differs
    for col <- [cfg.lft, cfg.rgt] do
      query = from(n in schema, where: field(n, ^col) >= ^start_val)
      query = apply_tree_condition(query, context_node, cfg)
      repo.update_all(query, inc: [{col, delta}])
    end

    :ok
  end

  defp move_node_as_root(repo, node, cfg) do
    old_tree = Map.get(node, cfg.tree)
    pk = get_primary_key(node)

    repo.transact(fn ->
      refreshed = repo.reload!(node)
      lft = Map.get(refreshed, cfg.lft)
      rgt = Map.get(refreshed, cfg.rgt)
      depth = Map.get(refreshed, cfg.depth)
      width = rgt - lft + 1

      subtree_query =
        from(n in node.__struct__,
          where: field(n, ^cfg.lft) >= ^lft,
          where: field(n, ^cfg.rgt) <= ^rgt,
          where: field(n, ^cfg.tree) == ^old_tree
        )

      repo.update_all(subtree_query,
        inc: [
          {cfg.lft, 1 - lft},
          {cfg.rgt, 1 - lft},
          {cfg.depth, -depth}
        ],
        set: [{cfg.tree, pk}]
      )

      for attr <- [cfg.lft, cfg.rgt] do
        close_query =
          from(n in node.__struct__,
            where: field(n, ^attr) > ^rgt,
            where: field(n, ^cfg.tree) == ^old_tree
          )

        repo.update_all(close_query, inc: [{attr, -width}])
      end

      {:ok, repo.reload!(node)}
    end)
  end

  defp validate_move(node, target, position) do
    cond do
      not loaded?(target) ->
        {:error, :cannot_move_target_is_new}

      get_primary_key(node) == get_primary_key(target) ->
        {:error, :cannot_move_to_itself}

      descendant_of?(target, node) ->
        {:error, :cannot_move_to_descendant}

      position in [:before, :after] && root?(target) ->
        {:error, :cannot_move_before_after_root}

      true ->
        :ok
    end
  end

  @spec calculate_insert_position(ns_node(), position()) :: {:ok, pos_integer(), 0 | 1}
  defp calculate_insert_position(target, position) do
    cfg = config(target)

    left = Map.get(target, cfg.lft)
    right = Map.get(target, cfg.rgt)

    case position do
      :prepend -> {:ok, left + 1, 1}
      :append -> {:ok, right, 1}
      :before -> {:ok, left, 0}
      :after -> {:ok, right + 1, 0}
    end
  end

  defp apply_tree_condition(query, _node, %{tree: false} = _cfg), do: query

  defp apply_tree_condition(query, node, %{tree: tree_attr} = _cfg) do
    tree_value = Map.get(node, tree_attr)
    from(n in query, where: field(n, ^tree_attr) == ^tree_value)
  end

  defp maybe_put_tree(attrs, _target, %{tree: false} = _cfg), do: attrs

  defp maybe_put_tree(attrs, target, %{tree: tree_attr} = _cfg) do
    Map.put(attrs, tree_attr, Map.get(target, tree_attr))
  end

  defp get_primary_key(node) do
    schema = node.__struct__
    [pk_field | _] = schema.__schema__(:primary_key)
    Map.get(node, pk_field)
  end

  # NOTE: composite keys not supported (is anyone needed it?), prototype below:
  # defp get_pk_field(schema) do
  #   [pk_field | _] = schema.__schema__(:primary_key)
  #   pk_field
  # end

  # defp get_pk_val(node) do
  #   Map.get(node, get_pk_field(node.__struct__))
  # end
end
