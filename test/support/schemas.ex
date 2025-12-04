defmodule NestedSets.Test.Schemas do
  @moduledoc """
  Test schemas for fixtures.
  """

  defmodule Category do
    @moduledoc false
    use Ecto.Schema
    use NestedSets.Schema

    @primary_key {:id, :id, autogenerate: true}
    @foreign_key_type :id

    schema "categories" do
      field :name, :string
      field :active, :boolean, default: true

      nested_sets_fields()

      timestamps()
    end
  end

  defmodule CategoryWithTree do
    @moduledoc false
    use Ecto.Schema

    use NestedSets.Schema,
      tree: :tree

    @primary_key {:id, :id, autogenerate: true}
    @foreign_key_type :id

    schema "categories_with_tree" do
      field :name, :string
      field :active, :boolean, default: true

      nested_sets_fields()

      timestamps()
    end
  end

  defmodule DummyNotNested do
    @moduledoc false
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :name, :string
      field :active, :boolean, default: true
    end
  end
end
