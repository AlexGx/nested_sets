import Config

config :nested_sets,
  ecto_repo: NestedSets.Test.Repo,
  default_repo: "postgres"

config :nested_sets, NestedSets.Test.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5434,
  database: "nested_sets_test#{System.get_env("MIX_TEST_PARTITION")}",
  migration_lock: false,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  priv: "test/support/postgres",
  show_sensitive_data_on_connection_error: true,
  stacktrace: true

config :nested_sets, NestedSets.Test.SqliteRepo,
  database:
    Path.expand(
      "../priv/nested_sets_sqlite_test#{System.get_env("MIX_TEST_PARTITION")}.db",
      Path.dirname(__ENV__.file)
    ),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5,
  journal_mode: :wal,
  synchronous: :normal,
  busy_timeout: 30000,
  queue_target: 5000,
  queue_interval: 5000,
  priv: "test/support/sqlite",
  migration_source: "nested_sets_sqlite_schema_migrations",
  show_sensitive_data_on_connection_error: true,
  stacktrace: true

config :nested_sets, NestedSets.Test.MysqlRepo,
  # prepare: :unnamed,
  # pool: Ecto.Adapters.SQL.Sandbox,
  pool: DBConnection.ConnectionPool,
  # System.schedulers_online() * 2,
  pool_size: 2,
  migration_lock: true,
  queue_target: 5000,
  queue_interval: 5000,
  priv: "test/support/mysql",
  migration_source: "nested_sets_mysql_schema_migrations",
  show_sensitive_data_on_connection_error: true,
  stacktrace: true,
  url:
    System.get_env("MYSQL_URL") ||
      "mysql://root:mysql@localhost:3307/nested_sets_test#{System.get_env("MIX_TEST_PARTITION")}"

config :nested_sets,
  ecto_repos: [NestedSets.Test.Repo, NestedSets.Test.SqliteRepo, NestedSets.Test.MysqlRepo]
