defmodule NestedSets.PredicatesTest do
  use NestedSets.Case, async: false
  import Ecto.Query

  alias NestedSets.Test.Repos
  alias NestedSets.Test.Schemas.{Category, CategoryWithTree}

  describe "Predicates" do
    setup %{repo: repo} do
      repo.delete_all(Category)

      # Electronics
      # └── Computers
      #     ├── Laptops
      #     └── Desktops

      {:ok, root} = NestedSets.make_root(repo, %Category{name: "Electronics"})
      {:ok, computers} = NestedSets.append_to(repo, %Category{name: "Computers"}, root)
      {:ok, _laptops} = NestedSets.append_to(repo, %Category{name: "Laptops"}, computers)
      {:ok, _desktops} = NestedSets.append_to(repo, %Category{name: "Desktops"}, computers)

      nodes =
        Category
        |> order_by(:lft)
        |> repo.all()
        |> Map.new(&{&1.name, &1})

      {:ok, nodes: nodes}
    end

    for {db_type, repo, tags} <- Repos.list() do
      @describetag Keyword.put(tags, :repo, repo)

      @tag db: db_type
      test "root?/1 (#{db_type})", %{nodes: nodes} do
        assert NestedSets.root?(nodes["Electronics"]) == true
        assert NestedSets.root?(nodes["Computers"]) == false
      end

      @tag db: db_type
      test "leaf?/1 (#{db_type})", %{nodes: nodes} do
        assert NestedSets.leaf?(nodes["Laptops"]) == true
        assert NestedSets.leaf?(nodes["Desktops"]) == true
        # Has children
        assert NestedSets.leaf?(nodes["Computers"]) == false
        assert NestedSets.leaf?(nodes["Electronics"]) == false
      end

      @tag db: db_type
      test "child_of?/2 (#{db_type})", %{nodes: nodes} do
        parent = nodes["Computers"]
        child = nodes["Laptops"]
        root = nodes["Electronics"]

        # direct child
        assert NestedSets.child_of?(child, parent)

        # grandchild is technically a child/descendant
        assert NestedSets.child_of?(child, root)

        # reverse is false
        refute NestedSets.child_of?(parent, child)

        # sibling is false
        sibling = nodes["Desktops"]
        refute NestedSets.child_of?(child, sibling)
      end

      @tag db: db_type
      test "child_of?/2 raise different schemas (#{db_type})", %{nodes: nodes} do
        parent = nodes["Computers"]
        child = %CategoryWithTree{name: "Child from other schema"}

        assert_raise ArgumentError,
                     ~r/^child_of\?\/2 expects both arguments to be structs of the same Schema/,
                     fn ->
                       NestedSets.child_of?(child, parent)
                     end
      end

      @tag db: db_type
      test "direct_child_of?/2 (#{db_type})", %{nodes: nodes} do
        parent = nodes["Computers"]
        child = nodes["Laptops"]
        root = nodes["Electronics"]

        # direct child
        assert NestedSets.direct_child_of?(child, parent)

        # grandchild is not a direct child
        refute NestedSets.direct_child_of?(child, root)

        # reverse is false
        refute NestedSets.direct_child_of?(parent, child)

        # sibling is false
        sibling = nodes["Desktops"]
        refute NestedSets.direct_child_of?(child, sibling)
      end

      @tag db: db_type
      test "direct_child_of?/2 raise different schemas (#{db_type})", %{nodes: nodes} do
        parent = nodes["Computers"]
        child = %CategoryWithTree{name: "Child from other schema"}

        assert_raise ArgumentError,
                     ~r/^direct_child_of\?\/2 expects both arguments to be structs of the same Schema/,
                     fn ->
                       NestedSets.direct_child_of?(child, parent)
                     end
      end

      @tag db: db_type
      test "descendant_count/1 (#{db_type})", %{nodes: nodes} do
        # Root has Computers, Laptops, Desktops = 3 descendants
        assert NestedSets.descendant_count(nodes["Electronics"]) == 3

        # Computers has Laptops, Desktops = 2 descendants
        assert NestedSets.descendant_count(nodes["Computers"]) == 2

        # Leaf has 0 descendants
        assert NestedSets.descendant_count(nodes["Laptops"]) == 0
      end
    end
  end

  describe "Predicates multi tree" do
    setup %{repo: repo} do
      repo.delete_all(CategoryWithTree)

      # Electronics
      # └── Computers
      #     ├── Laptops
      #     └── Desktops

      {:ok, root} = NestedSets.make_root(repo, %CategoryWithTree{name: "Electronics"})
      {:ok, computers} = NestedSets.append_to(repo, %CategoryWithTree{name: "Computers"}, root)
      {:ok, _laptops} = NestedSets.append_to(repo, %CategoryWithTree{name: "Laptops"}, computers)

      {:ok, _desktops} =
        NestedSets.append_to(repo, %CategoryWithTree{name: "Desktops"}, computers)

      nodes =
        CategoryWithTree
        |> order_by(:lft)
        |> repo.all()
        |> Map.new(&{&1.name, &1})

      {:ok, nodes: nodes}
    end

    for {db_type, repo, tags} <- Repos.list() do
      @describetag Keyword.put(tags, :repo, repo)

      @tag db: db_type
      test "root?/1 (#{db_type})", %{nodes: nodes} do
        assert NestedSets.root?(nodes["Electronics"]) == true
        assert NestedSets.root?(nodes["Computers"]) == false
      end

      @tag db: db_type
      test "leaf?/1 (#{db_type})", %{nodes: nodes} do
        assert NestedSets.leaf?(nodes["Laptops"]) == true
        assert NestedSets.leaf?(nodes["Desktops"]) == true
        # Has children
        assert NestedSets.leaf?(nodes["Computers"]) == false
        assert NestedSets.leaf?(nodes["Electronics"]) == false
      end

      @tag db: db_type
      test "child_of?/2 (#{db_type})", %{nodes: nodes} do
        parent = nodes["Computers"]
        child = nodes["Laptops"]
        root = nodes["Electronics"]

        # direct child
        assert NestedSets.child_of?(child, parent)

        # grandchild is technically a child/descendant
        assert NestedSets.child_of?(child, root)

        # reverse is false
        refute NestedSets.child_of?(parent, child)

        # sibling is false
        sibling = nodes["Desktops"]
        refute NestedSets.child_of?(child, sibling)
      end

      @tag db: db_type
      test "child_of?/2 raise different schemas (#{db_type})", %{nodes: nodes} do
        parent = nodes["Computers"]
        child = %Category{name: "Child from other schema"}

        assert_raise ArgumentError,
                     ~r/^child_of\?\/2 expects both arguments to be structs of the same Schema/,
                     fn ->
                       NestedSets.child_of?(child, parent)
                     end
      end

      @tag db: db_type
      test "direct_child_of?/2 (#{db_type})", %{nodes: nodes} do
        parent = nodes["Computers"]
        child = nodes["Laptops"]
        root = nodes["Electronics"]

        # direct child
        assert NestedSets.direct_child_of?(child, parent)

        # grandchild is not a direct child
        refute NestedSets.direct_child_of?(child, root)

        # reverse is false
        refute NestedSets.direct_child_of?(parent, child)

        # sibling is false
        sibling = nodes["Desktops"]
        refute NestedSets.direct_child_of?(child, sibling)
      end

      @tag db: db_type
      test "direct_child_of?/2 raise different schemas (#{db_type})", %{nodes: nodes} do
        parent = nodes["Computers"]
        child = %Category{name: "Child from other schema"}

        assert_raise ArgumentError,
                     ~r/^direct_child_of\?\/2 expects both arguments to be structs of the same Schema/,
                     fn ->
                       NestedSets.direct_child_of?(child, parent)
                     end
      end

      @tag db: db_type
      test "descendant_count/1 (#{db_type})", %{nodes: nodes} do
        # Root has Computers, Laptops, Desktops = 3 descendants
        assert NestedSets.descendant_count(nodes["Electronics"]) == 3

        # Computers has Laptops, Desktops = 2 descendants
        assert NestedSets.descendant_count(nodes["Computers"]) == 2

        # Leaf has 0 descendants
        assert NestedSets.descendant_count(nodes["Laptops"]) == 0
      end
    end
  end
end
