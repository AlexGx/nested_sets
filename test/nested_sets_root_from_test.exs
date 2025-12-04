defmodule NestedSets.SetsRootFromTest do
  use NestedSets.Case, async: false

  alias NestedSets.Test.Repos
  alias NestedSets.Test.Schemas.CategoryWithTree

  setup %{repo: repo} do
    repo.delete_all(CategoryWithTree)

    # Electronics (Root)
    # └── Computers
    #     ├── Laptops
    #     └── Desktops

    {:ok, root} = NestedSets.make_root(repo, %CategoryWithTree{name: "Electronics"})
    {:ok, computers} = NestedSets.append_to(repo, %CategoryWithTree{name: "Computers"}, root)
    {:ok, _laptops} = NestedSets.append_to(repo, %CategoryWithTree{name: "Laptops"}, computers)
    {:ok, _desktops} = NestedSets.append_to(repo, %CategoryWithTree{name: "Desktops"}, computers)

    nodes =
      CategoryWithTree
      |> repo.all()
      |> Map.new(&{&1.name, &1})

    {:ok, nodes: nodes}
  end

  describe "make_root_from/2" do
    for {db_type, repo, tags} <- Repos.list() do
      @describetag Keyword.put(tags, :repo, repo)

      @tag db: db_type
      test "promotes a child node to be a new root (starts a new tree) (#{db_type})", %{
        repo: repo,
        nodes: nodes
      } do
        # move "Computers" (and its subtree) out of "Electronics" to become its own Root
        node = nodes["Computers"]
        original_tree_id = node.tree

        {:ok, new_root} = NestedSets.make_root_from(repo, node)

        # verify new root props
        assert new_root.lft == 1
        assert new_root.depth == 0
        # "Computers" + "Laptops" + "Desktops" = 3 nodes * 2 = 6
        assert new_root.rgt == 6
        # tree id should equal its own id now
        assert new_root.tree == new_root.id
        assert new_root.tree != original_tree_id

        # verify children moved with it
        laptops = repo.get_by(CategoryWithTree, name: "Laptops")
        assert laptops.tree == new_root.tree
        # was 2, now 1 relative to new root
        assert laptops.depth == 1

        # verify old tree ("Electronics") closed the gap
        old_root = repo.get_by(CategoryWithTree, name: "Electronics")
        # "Electronics" should now be empty (lft: 1, rgt: 2)
        assert old_root.lft == 1
        assert old_root.rgt == 2
      end

      @tag db: db_type
      test "fails if node is already a root (#{db_type})", %{repo: repo, nodes: nodes} do
        node = nodes["Electronics"]
        assert {:error, :already_root} = NestedSets.make_root_from(repo, node)
      end
    end
  end
end
