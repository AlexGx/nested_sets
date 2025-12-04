defmodule NestedSets.HelpersTest do
  use NestedSets.Case, async: true

  alias NestedSets.Helpers
  alias NestedSets.Test.Schemas.Category

  setup do
    #   Root (1, 10, 0)
    #   ├── A (2, 7, 1)
    #   │   ├── A1 (3, 4, 2)
    #   │   └── A2 (5, 6, 2)
    #   └── B (8, 9, 1)

    nodes = [
      %Category{id: 1, name: "Root", lft: 1, rgt: 10, depth: 0},
      %Category{id: 2, name: "A", lft: 2, rgt: 7, depth: 1},
      %Category{id: 3, name: "A1", lft: 3, rgt: 4, depth: 2},
      %Category{id: 4, name: "A2", lft: 5, rgt: 6, depth: 2},
      %Category{id: 5, name: "B", lft: 8, rgt: 9, depth: 1}
    ]

    {:ok, nodes: nodes}
  end

  describe "build_tree/3" do
    test "converts flat list to nested map structure", %{nodes: nodes} do
      tree = Helpers.build_tree(nodes, Category)

      assert length(tree) == 1
      root = List.first(tree)
      assert root.name == "Root"
      assert length(root.children) == 2

      child_a = Enum.find(root.children, &(&1.name == "A"))
      child_b = Enum.find(root.children, &(&1.name == "B"))

      assert child_a
      assert child_b
      assert length(child_a.children) == 2
      assert Enum.empty?(child_b.children)

      assert Enum.map(child_a.children, & &1.name) == ["A1", "A2"]
    end

    test "handles custom child key", %{nodes: nodes} do
      tree = Helpers.build_tree(nodes, Category, child_key: :subcategories)
      root = List.first(tree)

      assert Map.has_key?(root, :subcategories)
      refute Map.has_key?(root, :children)
      assert length(root.subcategories) == 2
    end

    test "handles empty list" do
      assert Helpers.build_tree([], Category) == []
    end
  end

  describe "flatten_tree/2" do
    test "converts nested structure back to flat list with depth", %{nodes: nodes} do
      # reuse build_tree to get input
      tree = Helpers.build_tree(nodes, Category)
      flat = Helpers.flatten_tree(tree)

      # expected: [{Root, 0}, {A, 1}, {A1, 2}, {A2, 2}, {B, 1}]
      assert length(flat) == 5

      {node, depth} = List.first(flat)
      assert node.name == "Root"
      assert depth == 0
      # should remove children key
      refute Map.has_key?(node, :children)

      {node_a1, depth_a1} = Enum.at(flat, 2)
      assert node_a1.name == "A1"
      assert depth_a1 == 2
    end
  end

  describe "path_string/3" do
    test "builds breadcrumb string" do
      root = %Category{name: "Root"}
      parent = %Category{name: "Parent"}
      child = %Category{name: "Child"}

      ancestors = [root, parent]

      assert Helpers.path_string(child, ancestors) == "Root > Parent > Child"
    end

    test "respects options" do
      root = %Category{name: "Root"}
      ancestors = [root]
      node = %Category{name: "Leaf"}

      result = Helpers.path_string(node, ancestors, separator: " / ", name_field: :name)
      assert result == "Root / Leaf"
    end
  end

  describe "indent/2" do
    test "generates indentation string based on depth" do
      root = %Category{depth: 0}
      child = %Category{depth: 1}
      grandchild = %Category{depth: 2}

      assert Helpers.indent(root) == ""
      assert Helpers.indent(child) == "  "
      assert Helpers.indent(grandchild) == "    "
    end

    test "supports custom indent string and prefix" do
      node = %Category{depth: 2}
      assert Helpers.indent(node, indent_string: "-", prefix: "> ") == "--> "
    end
  end

  describe "validate_tree/2" do
    test "returns :ok for valid tree", %{nodes: nodes} do
      assert Helpers.validate_tree(nodes, Category) == :ok
    end

    test "detects lft >= rgt error" do
      invalid_nodes = [%Category{lft: 5, rgt: 4, depth: 0}]
      assert {:error, {:invalid_lft_rgt, _}} = Helpers.validate_tree(invalid_nodes, Category)
    end

    test "detects overlapping nodes" do
      # A: [1, 4]
      # B: [3, 6] -> overlap
      nodes = [
        %Category{lft: 1, rgt: 4, depth: 0},
        %Category{lft: 3, rgt: 6, depth: 0}
      ]

      assert {:error, {:overlap, _}} = Helpers.validate_tree(nodes, Category)
    end

    test "detects invalid depth (gap in hierarchy)" do
      # child depth is 2, but parent is 0 (should be 1)
      nodes = [
        %Category{lft: 1, rgt: 4, depth: 0},
        %Category{lft: 2, rgt: 3, depth: 2}
      ]

      assert {:error, {:invalid_depth, _, 1}} = Helpers.validate_tree(nodes, Category)
    end
  end

  describe "rebuild_from_hierarchy/2" do
    test "calculates lft/rgt/depth from simple nested map" do
      input = [
        %{
          name: "Root",
          children: [
            %{name: "A", children: []},
            %{name: "B", children: []}
          ]
        }
      ]

      result = Helpers.rebuild_from_hierarchy(input)

      # Root  (1, 6, 0)
      # A     (2, 3, 1)
      # B     (4, 5, 1)

      assert length(result) == 3

      {root_data, lft, rgt, depth} = Enum.find(result, fn {d, _, _, _} -> d.name == "Root" end)
      assert lft == 1
      assert rgt == 6
      assert depth == 0
      refute Map.has_key?(root_data, :children)

      {_a_data, lft, rgt, depth} = Enum.find(result, fn {d, _, _, _} -> d.name == "A" end)
      assert lft == 2
      assert rgt == 3
      assert depth == 1
    end

    test "handles deeply nested structure" do
      input = [
        %{
          name: "1",
          children: [
            %{
              name: "1.1",
              children: [
                %{name: "1.1.1", children: []}
              ]
            }
          ]
        }
      ]

      result = Helpers.rebuild_from_hierarchy(input)

      # "1"     (1, 6, 0)
      # "1.1"   (2, 5, 1)
      # "1.1.1" (3, 4, 2)

      leaf = Enum.find(result, fn {d, _, _, _} -> d.name == "1.1.1" end)
      {_, l, r, d} = leaf
      assert l == 3
      assert r == 4
      assert d == 2
    end
  end
end
