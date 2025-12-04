defmodule NestedSets.MoveNodeTest do
  use NestedSets.Case, async: false
  import Ecto.Query

  alias NestedSets.Test.Repos
  alias NestedSets.Test.Schemas.{Category}

  setup %{repo: repo} do
    repo.delete_all(Category)

    # Root
    # ├── A
    # │   ├── A1
    # │   └── A2
    # ├── B
    # └── C

    {:ok, root} = NestedSets.make_root(repo, %Category{name: "Root"})
    {:ok, child_a} = NestedSets.append_to(repo, %Category{name: "A"}, root)
    {:ok, _a1} = NestedSets.append_to(repo, %Category{name: "A1"}, child_a)
    {:ok, _a2} = NestedSets.append_to(repo, %Category{name: "A2"}, child_a)
    {:ok, _b} = NestedSets.append_to(repo, %Category{name: "B"}, root)
    {:ok, _c} = NestedSets.append_to(repo, %Category{name: "C"}, root)

    nodes =
      Category
      |> order_by(:lft)
      |> repo.all()
      |> Map.new(&{&1.name, &1})

    {:ok, nodes: nodes}
  end

  describe "prepend_to/3" do
    for {db_type, repo, tags} <- Repos.list() do
      @describetag Keyword.put(tags, :repo, repo)

      @tag db: db_type
      test "moves a node LEFT into another node (C inside A) (#{db_type})", %{
        repo: repo,
        nodes: nodes
      } do
        # C is currently to the right of A. Move it inside A, to the start.
        # expected: Root -> A -> [C, A1, A2], B
        target = nodes["A"]
        node_to_move = nodes["C"]

        assert {:ok, _} = NestedSets.prepend_to(repo, node_to_move, target)

        assert_tree(repo, [
          {"Root", 0},
          {"A", 1},
          # C is now first child of A
          {"C", 2},
          # A1 pushed after C
          {"A1", 2},
          {"A2", 2},
          {"B", 1}
        ])
      end

      @tag db: db_type
      test "moves a node RIGHT into another node (A inside B) (#{db_type})", %{
        repo: repo,
        nodes: nodes
      } do
        # A (and its subtree A1, A2) is to the left of B. Move A inside B.
        # expected: Root -> B -> [A -> [A1, A2]], C
        target = nodes["B"]
        node_to_move = nodes["A"]

        assert {:ok, _} = NestedSets.prepend_to(repo, node_to_move, target)

        assert_tree(repo, [
          {"Root", 0},
          {"B", 1},
          # A is now child of B
          {"A", 2},
          # A1 depth increased
          {"A1", 3},
          {"A2", 3},
          {"C", 1}
        ])
      end
    end
  end

  describe "append_to/3" do
    for {db_type, repo, tags} <- Repos.list() do
      @describetag Keyword.put(tags, :repo, repo)

      @tag db: db_type
      test "moves a node LEFT (C to end of A) (#{db_type})", %{repo: repo, nodes: nodes} do
        # move C (right side) to inside A (left side), but at the end.
        # expected: Root -> A -> [A1, A2, C], B
        target = nodes["A"]
        node_to_move = nodes["C"]

        assert {:ok, _} = NestedSets.append_to(repo, node_to_move, target)

        assert_tree(repo, [
          {"Root", 0},
          {"A", 1},
          {"A1", 2},
          {"A2", 2},
          # C is last child of A
          {"C", 2},
          {"B", 1}
        ])
      end
    end
  end

  describe "insert_before/3" do
    for {db_type, repo, tags} <- Repos.list() do
      @describetag Keyword.put(tags, :repo, repo)

      @tag db: db_type
      test "reorders siblings (swaps B to be before A) (#{db_type})", %{repo: repo, nodes: nodes} do
        # move B before A
        # expected: Root -> B, A -> [A1, A2], C
        target = nodes["A"]
        node_to_move = nodes["B"]

        assert {:ok, _} = NestedSets.insert_before(repo, node_to_move, target)

        assert_tree(repo, [
          {"Root", 0},
          # B first now
          {"B", 1},
          {"A", 1},
          {"A1", 2},
          {"A2", 2},
          {"C", 1}
        ])
      end
    end
  end

  describe "insert_after/3" do
    for {db_type, repo, tags} <- Repos.list() do
      @describetag Keyword.put(tags, :repo, repo)

      @tag db: db_type
      test "moves a node deeply nested out to a higher level (#{db_type})", %{
        repo: repo,
        nodes: nodes
      } do
        # move A1 (inside A) to be after B (sibling of B)
        # expected: Root -> A -> [A2], B, A1, C
        target = nodes["B"]
        node_to_move = nodes["A1"]

        assert {:ok, _} = NestedSets.insert_after(repo, node_to_move, target)

        assert_tree(repo, [
          {"Root", 0},
          {"A", 1},
          # A2 remains in A
          {"A2", 2},
          {"B", 1},
          # A1 is now sibling of B
          {"A1", 1},
          {"C", 1}
        ])
      end
    end
  end

  describe "validation" do
    for {db_type, repo, tags} <- Repos.list() do
      @describetag Keyword.put(tags, :repo, repo)

      @tag db: db_type
      test "cannot move node to self (#{db_type})", %{repo: repo, nodes: nodes} do
        node = nodes["A"]
        assert {:error, :cannot_move_to_itself} = NestedSets.append_to(repo, node, node)
      end

      @tag db: db_type
      test "cannot move node into its own descendant (#{db_type})", %{repo: repo, nodes: nodes} do
        node = nodes["A"]
        # A1 is child of A
        target = nodes["A1"]

        assert {:error, :cannot_move_to_descendant} = NestedSets.append_to(repo, node, target)
      end

      @tag db: db_type
      test "cannot move node before root (#{db_type})", %{repo: repo, nodes: nodes} do
        root = nodes["Root"]
        child = nodes["A"]

        assert {:error, :cannot_move_before_after_root} =
                 NestedSets.insert_before(repo, child, root)
      end
    end
  end

  # Helpers

  # verifies the entire tree structure matches the expected list of {name, depth}
  # implicitly checks lft/rgt integrity because we order by lft.
  defp assert_tree(repo, expected_structure) do
    actual =
      Category
      |> order_by(:lft)
      |> select([n], {n.name, n.depth, n.lft, n.rgt})
      |> repo.all()

    # verify structure (name + depth)
    actual_simplified = Enum.map(actual, fn {name, depth, _, _} -> {name, depth} end)
    assert actual_simplified == expected_structure

    # verify logic integrity:
    #  - no overlapping intervals for siblings (hard to check generically, but strict order helps)
    #  - check `rgt` > `lft`
    #  - check (`rgt`-`lft`-1)/2 == descendant count
    Enum.each(actual, fn {name, _, lft, rgt} ->
      assert lft < rgt, "node #{name} has invalid bounds: #{lft} >= #{rgt}"

      assert rem(rgt - lft, 2) == 1,
             "node #{name} width should be odd number (lft-rgt parity mismatch)"
    end)
  end
end
