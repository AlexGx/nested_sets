defmodule NestedSets.Test.MysqlRepo.Migrations.CreateTestTables do
  use Ecto.Migration

  import NestedSets.Migration

  def change do
    # Categories
    create table(:categories) do
      add :name, :string, null: false
      add :active, :boolean, default: true, null: false

      nested_sets_columns()

      timestamps()
    end

    create unique_index(:categories, [:name])

    # CategoriesWithTree
    create table(:categories_with_tree) do
      add :name, :string, null: false
      add :active, :boolean, default: true, null: false

      nested_sets_columns(use_tree: true)

      timestamps()
    end

    create unique_index(:categories_with_tree, [:name])
  end
end
