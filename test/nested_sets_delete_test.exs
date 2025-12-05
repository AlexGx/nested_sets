defmodule NestedSets.DeleteTest do
  use NestedSets.Case, async: false
  import Ecto.Query

  alias NestedSets.Test.Repos
  alias NestedSets.Test.Schemas.Category

  setup %{repo: repo} do
    repo.delete_all(Category)

    # Root (0)
    # ├───A (1)
    # │   ├── A1 (2)
    # │   └── A2 (2)
    # └── B (1)
    #     └── B1 (2)

    {:ok, root} = NestedSets.make_root(repo, %Category{name: "Root"})
    {:ok, a} = NestedSets.append_to(repo, %Category{name: "A"}, root)
    {:ok, _a1} = NestedSets.append_to(repo, %Category{name: "A1"}, a)
    {:ok, _a2} = NestedSets.append_to(repo, %Category{name: "A2"}, a)
    {:ok, b} = NestedSets.append_to(repo, %Category{name: "B"}, root)
    {:ok, _b1} = NestedSets.append_to(repo, %Category{name: "B1"}, b)

    nodes =
      Category
      |> order_by(:lft)
      |> repo.all()
      |> Map.new(&{&1.name, &1})

    {:ok, nodes: nodes}
  end

  describe "delete_with_children/2" do
    for {db_type, repo, tags} <- Repos.list() do
      @describetag Keyword.put(tags, :repo, repo)

      @tag db: db_type
      test "deletes a leaf node and closes gap (#{db_type})", %{nodes: nodes, repo: repo} do
        # target: A2 (leaf)
        # before: Root -> A -> [A1, A2], B
        # after:  Root -> A -> [A1], B (shifts left)

        target = nodes["A2"]
        assert {:ok, 1} = NestedSets.delete_with_children(repo, target)

        refute repo.get(Category, target.id)

        assert_tree(repo, [
          {"Root", 0},
          {"A", 1},
          {"A1", 2},
          # B and B1 shift left to close gap
          {"B", 1},
          {"B1", 2}
        ])
      end

      @tag db: db_type
      test "deletes a node and all its descendants (#{db_type})", %{nodes: nodes, repo: repo} do
        # target: A (Has children A1, A2)
        # expected: A, A1, A2 removed. B shifts left.

        target = nodes["A"]

        # should delete A, A1, A2 (3 nodes)
        assert {:ok, 3} = NestedSets.delete_with_children(repo, target)

        # verify deletions
        refute repo.get(Category, nodes["A"].id)
        refute repo.get(Category, nodes["A1"].id)
        refute repo.get(Category, nodes["A2"].id)

        # verify B shifted correctly
        assert_tree(repo, [
          {"Root", 0},
          {"B", 1},
          {"B1", 2}
        ])
      end

      @tag db: db_type
      test "deletes the root node and wipes the tree (#{db_type})", %{nodes: nodes, repo: repo} do
        target = nodes["Root"]

        # should delete 6 nodes (everything)
        assert {:ok, 6} = NestedSets.delete_with_children(repo, target)

        assert repo.aggregate(Category, :count) == 0
      end
    end
  end

  describe "delete_node/2 (Promotion)" do
    for {db_type, repo, tags} <- Repos.list() do
      @describetag Keyword.put(tags, :repo, repo)

      @tag db: db_type
      test "deletes a leaf node (behaves like standard delete) (#{db_type})", %{
        nodes: nodes,
        repo: repo
      } do
        target = nodes["A2"]
        assert {:ok, _deleted_node} = NestedSets.delete_node(repo, target)

        refute repo.get(Category, target.id)

        assert_tree(repo, [
          {"Root", 0},
          {"A", 1},
          {"A1", 2},
          {"B", 1},
          {"B1", 2}
        ])
      end

      @tag db: db_type
      test "deletes node and promotes children up one level (#{db_type})", %{
        nodes: nodes,
        repo: repo
      } do
        # target: A (Children A1, A2)
        # before: Root -> A(1) -> A1(2), A2(2)
        # after:  Root -> A1(1), A2(1), B(1)

        target = nodes["A"]
        assert {:ok, _deleted} = NestedSets.delete_node(repo, target)

        refute repo.get(Category, target.id)

        # Check A1 and A2 exists
        a1 = repo.get_by(Category, name: "A1")
        a2 = repo.get_by(Category, name: "A2")

        assert a1.depth == 1
        assert a2.depth == 1

        assert_tree(repo, [
          {"Root", 0},
          # promoted from 2 to 1
          {"A1", 1},
          # promoted from 2 to 1
          {"A2", 1},
          {"B", 1},
          {"B1", 2}
        ])
      end

      @tag db: db_type
      test "prevents deleting the root node if it has any child (#{db_type})", %{nodes: nodes, repo: repo} do
        target = nodes["Root"]
        assert {:error, :cannot_delete_non_empty_root} = NestedSets.delete_node(repo, target)

        # ensure nothing changed
        assert repo.aggregate(Category, :count) == 6
      end
    end
  end

  # Helpers

  defp assert_tree(repo, expected_structure) do
    actual =
      Category
      |> order_by(:lft)
      |> select([n], {n.name, n.depth, n.lft, n.rgt})
      |> repo.all()

    actual_simplified = Enum.map(actual, fn {name, depth, _, _} -> {name, depth} end)
    assert actual_simplified == expected_structure

    # logic integrity checks
    Enum.each(actual, fn {name, _, lft, rgt} ->
      assert lft < rgt, "Node #{name} invalid bounds"
      assert rem(rgt - lft, 2) == 1, "Node #{name} width parity error"
    end)
  end
end
