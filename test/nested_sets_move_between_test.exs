defmodule NestedSets.MoveBetweenTreesTest do
  use NestedSets.Case, async: false
  import Ecto.Query

  alias NestedSets.Test.Repos
  alias NestedSets.Test.Schemas.CategoryWithTree

  setup %{repo: repo} do
    repo.delete_all(CategoryWithTree)

    # Electronics (0)
    # └── Computers (1)
    #     ├── Laptops (2)
    #     └── Desktops (2)
    {:ok, root1} = NestedSets.make_root(repo, %CategoryWithTree{name: "Electronics"})
    {:ok, computers} = NestedSets.append_to(repo, %CategoryWithTree{name: "Computers"}, root1)
    {:ok, _laptops} = NestedSets.append_to(repo, %CategoryWithTree{name: "Laptops"}, computers)

    {:ok, _desktops} =
      NestedSets.append_to(repo, %CategoryWithTree{name: "Desktops"}, computers)

    # Furniture (0)
    # └── Chairs (1)
    #     └── Office Chairs (2)
    {:ok, root2} = NestedSets.make_root(repo, %CategoryWithTree{name: "Furniture"})
    {:ok, chairs} = NestedSets.append_to(repo, %CategoryWithTree{name: "Chairs"}, root2)

    {:ok, _office} =
      NestedSets.append_to(repo, %CategoryWithTree{name: "Office Chairs"}, chairs)

    nodes =
      CategoryWithTree
      |> repo.all()
      |> Map.new(&{&1.name, &1})

    {:ok, nodes: nodes, root1_id: root1.id, root2_id: root2.id}
  end

  describe "move between trees" do
    for {db_type, repo, tags} <- Repos.list() do
      @describetag Keyword.put(tags, :repo, repo)

      @tag db: db_type
      test "moves a subtree from Tree 1 to Tree 2 (append) (#{db_type})", %{
        repo: repo,
        nodes: nodes,
        root1_id: t1_id,
        root2_id: t2_id
      } do
        # move "Computers" (and its children) to "Furniture"
        # target: append to "Furniture" (Root of tree 2)

        node = nodes["Computers"]
        target = nodes["Furniture"]

        assert {:ok, moved_node} = NestedSets.append_to(repo, node, target)

        # verify node id didn't change, but tree id did
        assert moved_node.id == node.id
        assert moved_node.tree == t2_id

        # test descendants moved and updated tree id
        laptops = repo.get_by(CategoryWithTree, name: "Laptops")
        assert laptops.tree == t2_id

        # test target tree structure
        # "Furniture" (0) -> "Chairs" (1) -> "Office Chairs" (2), "Computers" (1) -> "Laptops" (2), "Desktops" (2)
        assert_tree(repo, t2_id, [
          {"Furniture", 0},
          {"Chairs", 1},
          {"Office Chairs", 2},
          # moved here
          {"Computers", 1},
          {"Laptops", 2},
          {"Desktops", 2}
        ])

        # test source tree structure (gap closed)
        # "Electronics" should be free of children
        assert_tree(repo, t1_id, [
          {"Electronics", 0}
        ])
      end

      @tag db: db_type
      test "moves a node into a specific position in Tree 2 (prepend to child) (#{db_type})", %{
        repo: repo,
        nodes: nodes,
        root1_id: t1_id,
        root2_id: t2_id
      } do
        # make "Computers" to be the first child of "Chairs" in second tree

        node = nodes["Computers"]
        target = nodes["Chairs"]

        assert {:ok, _} = NestedSets.prepend_to(repo, node, target)

        # check target tree
        # "Furniture" -> "Chairs" -> ["Computers" -> ["Laptops", "Desktops"], "Office Chairs"]
        assert_tree(repo, t2_id, [
          {"Furniture", 0},
          {"Chairs", 1},
          # depth increased (0->1 in old tree, now 1->2)
          {"Computers", 2},
          {"Laptops", 3},
          {"Desktops", 3},
          {"Office Chairs", 2}
        ])

        # check source tree
        assert_tree(repo, t1_id, [
          {"Electronics", 0}
        ])
      end

      @tag db: db_type
      test "moves a node before another node in Tree 2 (#{db_type})", %{
        repo: repo,
        nodes: nodes,
        root2_id: t2_id
      } do
        # move "Laptops" (first tree, child) before "Chairs" (second tree, child)
        # "Laptops" leaves its parent "Computers" behind

        node = nodes["Laptops"]
        target = nodes["Chairs"]

        assert {:ok, _} = NestedSets.insert_before(repo, node, target)

        # expected: "Furniture" -> "Laptops", "Chairs" -> "Office Chairs"
        assert_tree(repo, t2_id, [
          {"Furniture", 0},
          # Moved to depth 1
          {"Laptops", 1},
          {"Chairs", 1},
          {"Office Chairs", 2}
        ])

        # source tree: "Electronics" -> "Computers" -> "Desktops"
        root1 = nodes["Electronics"]

        assert_tree(repo, root1.tree, [
          {"Electronics", 0},
          {"Computers", 1},
          {"Desktops", 2}
        ])
      end
    end
  end

  # Helpers

  defp assert_tree(repo, tree_id, expected_structure) do
    actual =
      CategoryWithTree
      |> where([c], c.tree == ^tree_id)
      |> order_by(:lft)
      |> select([n], {n.name, n.depth, n.lft, n.rgt})
      |> repo.all()

    actual_simplified = Enum.map(actual, fn {name, depth, _, _} -> {name, depth} end)
    assert actual_simplified == expected_structure

    # integrity checks
    Enum.each(actual, fn {name, _, lft, rgt} ->
      assert lft < rgt, "Node #{name} invalid bounds"
      assert rem(rgt - lft, 2) == 1, "Node #{name} width parity error"
    end)
  end
end
