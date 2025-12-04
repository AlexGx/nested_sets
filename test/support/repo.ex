defmodule NestedSets.Test.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :nested_sets,
    adapter: Ecto.Adapters.Postgres
end

defmodule NestedSets.Test.SqliteRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :nested_sets,
    adapter: Ecto.Adapters.SQLite3
end

defmodule NestedSets.Test.MysqlRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :nested_sets,
    adapter: Ecto.Adapters.MyXQL
end

defmodule NestedSets.Test.Repos do
  @moduledoc false

  alias NestedSets.Test.{Repo, SqliteRepo, MysqlRepo}

  @type repo_config :: {atom(), module(), keyword()}

  @spec list() :: [repo_config()]
  def list do
    [
      {:postgres, Repo, []},
      {:sqlite, SqliteRepo, [sqlite: true]},
      {:mysql, MysqlRepo, [mysql: true]}
    ]
  end
end
