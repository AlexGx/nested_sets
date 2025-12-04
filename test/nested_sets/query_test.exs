defmodule NestedSets.QueryTest do
  use NestedSets.Case, async: true

  alias NestedSets.Test.Repos
  alias NestedSets.Query
  alias NestedSets.Test.Schemas.{Category, CategoryWithTree}

  describe "single tree queries" do
    setup %{repo: repo} do
      repo.delete_all(Category)

      # Root (0)
      # ├── A (1)
      # │   ├── A1 (2)
      # │   └── A2 (2)
      # └── B (1)
      #     ├── B1 (2)
      #     └── B2 (2)

      {:ok, root} = NestedSets.make_root(repo, %Category{name: "Root"})
      {:ok, a} = NestedSets.append_to(repo, %Category{name: "A"}, root)
      {:ok, _a1} = NestedSets.append_to(repo, %Category{name: "A1"}, a)
      {:ok, _a2} = NestedSets.append_to(repo, %Category{name: "A2"}, a)
      {:ok, b} = NestedSets.append_to(repo, %Category{name: "B"}, root)
      {:ok, _b1} = NestedSets.append_to(repo, %Category{name: "B1"}, b)
      {:ok, _b2} = NestedSets.append_to(repo, %Category{name: "B2"}, b)

      nodes =
        Category
        |> repo.all()
        |> Map.new(&{&1.name, &1})

      {:ok, nodes: nodes}
    end

    for {db_type, repo, tags} <- Repos.list() do
      @describetag Keyword.put(tags, :repo, repo)

      @tag db: db_type
      test "ancestors/2 returns all ancestors in order (#{db_type})", %{nodes: nodes, repo: repo} do
        ancestors = Category |> Query.ancestors(nodes["A1"]) |> repo.all()
        assert length(ancestors) == 2
        assert Enum.map(ancestors, & &1.name) == ["Root", "A"]
      end

      @tag db: db_type
      test "ancestors/3 with depth limit = 1 (#{db_type})", %{nodes: nodes, repo: repo} do
        ancestors = Category |> Query.ancestors(nodes["A1"], depth: 1) |> repo.all()
        assert length(ancestors) == 1
        assert hd(ancestors).name == "A"
      end

      @tag db: db_type
      test "parents/2 is alias for ancestors/2 (#{db_type})", %{nodes: nodes, repo: repo} do
        ancestors = Category |> Query.ancestors(nodes["A1"]) |> repo.all()
        parents = Category |> Query.parents(nodes["A1"]) |> repo.all()
        assert ancestors == parents
      end

      @tag db: db_type
      test "descendants/2 returns all descendants in order (#{db_type})", %{
        nodes: nodes,
        repo: repo
      } do
        descendants = Category |> Query.descendants(nodes["Root"]) |> repo.all()
        assert length(descendants) == 6
        assert Enum.map(descendants, & &1.name) == ["A", "A1", "A2", "B", "B1", "B2"]
      end

      @tag db: db_type
      test "descendants/2 for subtree (#{db_type})", %{nodes: nodes, repo: repo} do
        descendants = Category |> Query.descendants(nodes["A"]) |> repo.all()
        assert length(descendants) == 2
        assert Enum.map(descendants, & &1.name) == ["A1", "A2"]
      end

      @tag db: db_type
      test "descendants/3 with depth limit (#{db_type})", %{nodes: nodes, repo: repo} do
        descendants = Category |> Query.descendants(nodes["Root"], depth: 1) |> repo.all()
        assert length(descendants) == 2
        assert Enum.map(descendants, & &1.name) == ["A", "B"]
      end

      @tag db: db_type
      test "children/2 is alias for descendants/2 (#{db_type})", %{nodes: nodes, repo: repo} do
        descendants = Category |> Query.descendants(nodes["Root"]) |> repo.all()
        children = Category |> Query.children(nodes["Root"]) |> repo.all()
        assert descendants == children
      end

      @tag db: db_type
      test "direct_children/2 returns only immediate children (#{db_type})", %{
        nodes: nodes,
        repo: repo
      } do
        children = Category |> Query.direct_children(nodes["Root"]) |> repo.all()
        assert length(children) == 2
        assert Enum.map(children, & &1.name) == ["A", "B"]
      end

      @tag db: db_type
      test "leaves/2 returns leaf nodes under parent (#{db_type})", %{nodes: nodes, repo: repo} do
        leaves = Category |> Query.leaves(nodes["Root"]) |> repo.all()
        assert length(leaves) == 4
        assert Enum.map(leaves, & &1.name) == ["A1", "A2", "B1", "B2"]
      end

      @tag db: db_type
      test "leaves/2 for subtree (#{db_type})", %{nodes: nodes, repo: repo} do
        leaves = Category |> Query.leaves(nodes["A"]) |> repo.all()
        assert length(leaves) == 2
        assert Enum.map(leaves, & &1.name) == ["A1", "A2"]
      end

      @tag db: db_type
      test "prev_sibling/2 returns previous sibling (#{db_type})", %{nodes: nodes, repo: repo} do
        prev = Category |> Query.prev_sibling(nodes["A2"]) |> repo.one()
        assert prev.name == "A1"
      end

      @tag db: db_type
      test "prev_sibling/2 returns nil for first child (#{db_type})", %{nodes: nodes, repo: repo} do
        prev = Category |> Query.prev_sibling(nodes["A1"]) |> repo.one()
        assert prev == nil
      end

      @tag db: db_type
      test "prev/2 is alias for prev_sibling/2 (#{db_type})", %{nodes: nodes, repo: repo} do
        prev1 = Category |> Query.prev_sibling(nodes["A2"]) |> repo.one()
        prev2 = Category |> Query.prev(nodes["A2"]) |> repo.one()
        assert prev1 == prev2
      end

      @tag db: db_type
      test "next_sibling/2 returns next sibling (#{db_type})", %{nodes: nodes, repo: repo} do
        next = Category |> Query.next_sibling(nodes["A1"]) |> repo.one()
        assert next.name == "A2"
      end

      @tag db: db_type
      test "next_sibling/2 returns nil for last child (#{db_type})", %{nodes: nodes, repo: repo} do
        next = Category |> Query.next_sibling(nodes["A2"]) |> repo.one()
        assert next == nil
      end

      @tag db: db_type
      test "next/2 is alias for next_sibling/2 (#{db_type})", %{nodes: nodes, repo: repo} do
        next1 = Category |> Query.next_sibling(nodes["A1"]) |> repo.one()
        next2 = Category |> Query.next(nodes["A1"]) |> repo.one()
        assert next1 == next2
      end

      @tag db: db_type
      test "siblings/2 returns all siblings except self (#{db_type})", %{nodes: nodes, repo: repo} do
        siblings = Category |> Query.siblings(nodes["A1"]) |> repo.all()
        assert length(siblings) == 1
        assert hd(siblings).name == "A2"
      end

      @tag db: db_type
      test "siblings/2 for node with multiple siblings (#{db_type})", %{nodes: nodes, repo: repo} do
        siblings = Category |> Query.siblings(nodes["A"]) |> repo.all()
        assert length(siblings) == 1
        assert hd(siblings).name == "B"
      end

      @tag db: db_type
      test "roots/1 returns all root nodes (#{db_type})", %{repo: repo} do
        roots = Category |> Query.roots() |> repo.all()
        assert length(roots) == 1
        assert hd(roots).name == "Root"
      end

      @tag db: db_type
      test "root/2 returns root for a node (#{db_type})", %{nodes: nodes, repo: repo} do
        root = Category |> Query.root(nodes["A1"]) |> repo.one()
        assert root.name == "Root"
        assert root.id == nodes["Root"].id
      end

      @tag db: db_type
      test "subtree/2 returns node and all descendants (#{db_type})", %{nodes: nodes, repo: repo} do
        subtree = Category |> Query.subtree(nodes["A"]) |> repo.all()
        assert length(subtree) == 3
        assert Enum.map(subtree, & &1.name) == ["A", "A1", "A2"]
      end

      @tag db: db_type
      test "at_depth/2 returns nodes at specific depth (#{db_type})", %{repo: repo} do
        depth_1 = Category |> Query.at_depth(1) |> repo.all()
        depth_2 = Category |> Query.at_depth(2) |> repo.all()
        assert length(depth_1) == 2
        assert Enum.map(depth_1, & &1.name) == ["A", "B"]
        assert length(depth_2) == 4
        assert Enum.map(depth_2, & &1.name) == ["A1", "A2", "B1", "B2"]
      end
    end
  end

  describe "multi-tree queries" do
    setup %{repo: repo} do
      repo.delete_all(CategoryWithTree)

      # first tree: Root1 -> Child1
      {:ok, root1} = NestedSets.make_root(repo, %CategoryWithTree{name: "Root1"})
      {:ok, _child1} = NestedSets.append_to(repo, %CategoryWithTree{name: "Child1"}, root1)

      # second tree: Root2 -> Child2
      {:ok, root2} = NestedSets.make_root(repo, %CategoryWithTree{name: "Root2"})
      {:ok, _child2} = NestedSets.append_to(repo, %CategoryWithTree{name: "Child2"}, root2)

      nodes =
        CategoryWithTree
        |> repo.all()
        |> Map.new(&{&1.name, &1})

      {:ok, nodes: nodes}
    end

    for {db_type, repo, tags} <- Repos.list() do
      @describetag Keyword.put(tags, :repo, repo)

      @tag db: db_type
      test "descendants respects tree isolation (#{db_type})", %{nodes: nodes, repo: repo} do
        # should only get descendants from tree 1
        descendants = CategoryWithTree |> Query.descendants(nodes["Root1"]) |> repo.all()

        assert length(descendants) == 1
        assert hd(descendants).name == "Child1"
      end

      @tag db: db_type
      test "ancestors respects tree isolation (#{db_type})", %{nodes: nodes, repo: repo} do
        ancestors = CategoryWithTree |> Query.ancestors(nodes["Child1"]) |> repo.all()

        assert length(ancestors) == 1
        assert hd(ancestors).name == "Root1"
      end

      @tag db: db_type
      test "roots/1 returns all roots across trees (#{db_type})", %{repo: repo} do
        roots = CategoryWithTree |> Query.roots() |> repo.all()

        assert length(roots) == 2
        names = Enum.map(roots, & &1.name)
        assert "Root1" in names
        assert "Root2" in names
      end

      @tag db: db_type
      test "in_tree/2 filters by tree_id (#{db_type})", %{nodes: nodes, repo: repo} do
        root_1_tree = nodes["Root1"].tree
        nodes = CategoryWithTree |> Query.in_tree(root_1_tree) |> repo.all()
        assert length(nodes) == 2
        assert Enum.all?(nodes, fn node -> node.tree == root_1_tree end)
      end

      @tag db: db_type
      test "in_tree/2 filters by node struct (#{db_type})", %{nodes: nodes, repo: repo} do
        tree_nodes = CategoryWithTree |> Query.in_tree(nodes["Child1"]) |> repo.all()
        root_1_tree = nodes["Root1"].tree
        assert length(tree_nodes) == 2
        assert Enum.all?(tree_nodes, fn node -> node.tree == root_1_tree end)
      end
    end
  end

  describe "query composition" do
    setup %{repo: repo} do
      repo.delete_all(Category)

      {:ok, root} = NestedSets.make_root(repo, %Category{name: "Root"})
      {:ok, a} = NestedSets.append_to(repo, %Category{name: "A"}, root)
      {:ok, _a1} = NestedSets.append_to(repo, %Category{name: "A1"}, a)
      {:ok, _a2} = NestedSets.append_to(repo, %Category{name: "A2"}, a)

      nodes =
        Category
        |> repo.all()
        |> Map.new(&{&1.name, &1})

      {:ok, nodes: nodes}
    end

    for {db_type, repo, tags} <- Repos.list() do
      @describetag Keyword.put(tags, :repo, repo)

      @tag db: db_type
      test "queries are composable with additional where clauses (#{db_type})", %{
        nodes: nodes,
        repo: repo
      } do
        result =
          Category
          |> Query.descendants(nodes["Root"])
          |> where([n], n.name == "A1")
          |> repo.all()

        assert length(result) == 1
        assert hd(result).name == "A1"
      end

      @tag db: db_type
      test "queries work with select (#{db_type})", %{nodes: nodes, repo: repo} do
        names =
          Category
          |> Query.descendants(nodes["A"])
          |> select([n], n.name)
          |> repo.all()

        assert names == ["A1", "A2"]
      end

      @tag db: db_type
      test "queries work with preload on Ecto.Query (#{db_type})", %{nodes: nodes, repo: repo} do
        base_query = from(c in Category, where: not is_nil(c.id))

        result =
          base_query
          |> Query.descendants(nodes["Root"], depth: 1)
          |> repo.all()

        assert length(result) == 1
        assert hd(result).name == "A"
      end
    end
  end
end
