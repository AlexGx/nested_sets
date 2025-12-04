defmodule NestedSets.SchemaTest do
  use ExUnit.Case, async: true

  defmodule DefaultSchema do
    @moduledoc false
    use Ecto.Schema
    use NestedSets.Schema

    schema "default_items" do
      field :name, :string
      nested_sets_fields()
    end
  end

  defmodule DefaultTreeSchema do
    @moduledoc false
    use Ecto.Schema

    use NestedSets.Schema,
      tree: true

    schema "default_items" do
      field :name, :string
      nested_sets_fields()
    end
  end

  defmodule CustomFieldSchema do
    @moduledoc false
    use Ecto.Schema

    use NestedSets.Schema,
      lft: :start_node,
      rgt: :end_node,
      depth: :level

    schema "custom_items" do
      field :name, :string
      nested_sets_fields()
    end
  end

  defmodule MultiTreeSchema do
    @moduledoc false
    use Ecto.Schema

    use NestedSets.Schema,
      tree: :organization_id

    schema "multi_tree_items" do
      field :name, :string
      nested_sets_fields()
    end
  end

  describe "__nested_sets_config__/0" do
    test "returns default configuration" do
      config = DefaultSchema.__nested_sets_config__()

      assert config.lft == :lft
      assert config.rgt == :rgt
      assert config.depth == :depth
      assert config.tree == false
    end

    test "returns custom configuration" do
      config = CustomFieldSchema.__nested_sets_config__()

      assert config.lft == :start_node
      assert config.rgt == :end_node
      assert config.depth == :level
      assert config.tree == false
    end

    test "returns configuration with tree attribute" do
      config = MultiTreeSchema.__nested_sets_config__()

      assert config.tree == :organization_id
    end
  end

  describe "nested_sets_fields/0" do
    test "defines default fields with correct types" do
      fields = DefaultSchema.__schema__(:fields)

      assert :lft in fields
      assert :rgt in fields
      assert :depth in fields

      assert DefaultSchema.__schema__(:type, :lft) == :integer
      assert DefaultSchema.__schema__(:type, :rgt) == :integer
      assert DefaultSchema.__schema__(:type, :depth) == :integer
    end

    test "defines default depth value" do
      struct = struct(DefaultSchema)
      assert struct.depth == 0
    end

    test "similar to default depth test but with name" do
      struct = %DefaultSchema{name: "Bar"}
      assert struct.name == "Bar"
      assert struct.depth == 0
    end

    test "does not define a tree field by default" do
      fields = DefaultSchema.__schema__(:fields)
      refute :tree_id in fields
    end

    test "defines custom named fields" do
      fields = CustomFieldSchema.__schema__(:fields)

      assert :start_node in fields
      assert :end_node in fields
      assert :level in fields

      # ensure defaults were NOT created
      refute :lft in fields
      refute :rgt in fields
      refute :depth in fields
    end

    test "defines tree attribute field when configured" do
      fields = MultiTreeSchema.__schema__(:fields)

      assert :organization_id in fields
      assert MultiTreeSchema.__schema__(:type, :organization_id) == :integer
    end

    test "defines default tree schema fields" do
      fields = DefaultTreeSchema.__schema__(:fields)
      assert :tree in fields
    end
  end
end
