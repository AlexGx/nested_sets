defmodule NestedSetsRootTest do
  use NestedSets.Case, async: false

  import NestedSets.Fixtures

  alias NestedSets.Test.Repos
  alias NestedSets.Test.Schemas.{Category, CategoryWithTree, DummyNotNested}

  setup %{repo: repo} do
    repo.delete_all(Category)
    repo.delete_all(CategoryWithTree)

    :ok
  end

  describe "root tests" do
    for {db_type, repo, tags} <- Repos.list() do
      @describetag Keyword.put(tags, :repo, repo)

      @tag db: db_type
      test "make_root simple (#{db_type})", %{repo: repo} do
        node = %Category{name: "Root"}
        assert {:ok, _result} = NestedSets.make_root(repo, node)
      end

      @tag db: db_type
      test "make_root simple with :root_already_exists (#{db_type})", %{repo: repo} do
        node = %Category{name: "Root"}
        assert {:ok, _result} = NestedSets.make_root(repo, node)
        assert {:error, :root_already_exists} = NestedSets.make_root(repo, node)
      end

      @tag db: db_type
      test "make_root with tree (#{db_type})", %{repo: repo} do
        node = %CategoryWithTree{name: "Root"}
        assert {:ok, result} = NestedSets.make_root(repo, node)
        assert 0 == NestedSets.descendant_count(result)
      end
    end
  end

  describe "dummy test" do
    for {db_type, repo, tags} <- Repos.list() do
      @describetag Keyword.put(tags, :repo, repo)

      @tag db: db_type
      test "must raise when make root with non nested sets (#{db_type})", %{repo: repo} do
        assert_raise ArgumentError, fn ->
          node = %DummyNotNested{name: "Root"}
          NestedSets.make_root(repo, node)
        end
      end
    end
  end
end
