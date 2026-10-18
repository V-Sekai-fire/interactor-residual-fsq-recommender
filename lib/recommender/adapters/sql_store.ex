# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Recommender.Adapters.SqlStore do
  @moduledoc """
  SQLite persistence for the `rfr` CLI.

  `with_db/2` opens one connection, ensures the schema, runs the caller's function and closes
  it. The database is `:db`, then `RFR_DB`. With a `weftfdb` extension (`:weftfdb_extension`,
  then `RFR_WEFTFDB_EXTENSION`) the default is `file:rfr.v1?vfs=weft_fdb`, whose pages live in
  FoundationDB through datasource-store's VFS; without one it is `<data-dir>/rfr.sqlite3`.

  Schema — items are semantic IDs, transitions the hetero-associative counts:

      items(item_id TEXT PRIMARY KEY, t0 INTEGER, t1 INTEGER, t2 INTEGER, t3 INTEGER)
      transitions(prev TEXT, next TEXT, n INTEGER, PRIMARY KEY (prev, next))
  """

  alias Exqlite.Sqlite3

  @type opts :: %{
          optional(:data_dir) => String.t(),
          optional(:db) => String.t() | nil,
          optional(:weftfdb_extension) => String.t() | nil
        }

  @doc "Default data directory (override with `--data-dir` or `RFR_DATA_DIR`)."
  def default_data_dir do
    System.get_env("RFR_DATA_DIR") ||
      Path.join(System.user_home!(), ".residual-fsq-recommender")
  end

  @doc """
  Run `fun.(conn)` against the store, opening one connection and closing it after.
  Returns `fun`'s result, or `{:error, reason}` when the store cannot be opened.
  """
  @spec with_db(opts(), (Sqlite3.db() -> result)) :: result | {:error, term()} when result: var
  def with_db(opts \\ %{}, fun) do
    extension = opts[:weftfdb_extension] || System.get_env("RFR_WEFTFDB_EXTENSION")

    with :ok <- load_extension(extension),
         {:ok, conn} <- Sqlite3.open(database(opts, extension)) do
      try do
        :ok = ensure_schema(conn)
        fun.(conn)
      after
        Sqlite3.close(conn)
      end
    end
  end

  defp database(opts, extension) do
    cond do
      db = opts[:db] || System.get_env("RFR_DB") ->
        db

      extension ->
        "file:rfr.v1?vfs=weft_fdb"

      true ->
        dir = opts[:data_dir] || default_data_dir()
        File.mkdir_p!(dir)
        Path.join(dir, "rfr.sqlite3")
    end
  end

  # The weft_fdb VFS registers process-wide, so it is loaded once on a throwaway connection.
  defp load_extension(nil), do: :ok

  defp load_extension(path) do
    key = {__MODULE__, :weftfdb, path}

    if :persistent_term.get(key, false) do
      :ok
    else
      {:ok, conn} = Sqlite3.open(":memory:")

      try do
        with :ok <- Sqlite3.enable_load_extension(conn, true),
             :ok <-
               Sqlite3.execute(
                 conn,
                 "SELECT load_extension('#{String.replace(path, "'", "''")}')"
               ) do
          :persistent_term.put(key, true)
          :ok
        end
      after
        Sqlite3.close(conn)
      end
    end
  end

  ## Item / transition persistence (Recommender.Ports.ItemSink / ItemSource)

  @behaviour Recommender.Ports.ItemSink
  @behaviour Recommender.Ports.ItemSource

  @impl Recommender.Ports.ItemSink
  def upsert_item(conn, item_id, [t0, t1, t2, t3]) do
    query!(
      conn,
      """
      INSERT INTO items (item_id, t0, t1, t2, t3) VALUES (?1, ?2, ?3, ?4, ?5)
      ON CONFLICT (item_id) DO UPDATE
        SET t0 = excluded.t0, t1 = excluded.t1, t2 = excluded.t2, t3 = excluded.t3
      """,
      [item_id, t0, t1, t2, t3]
    )

    :ok
  end

  @impl Recommender.Ports.ItemSink
  def record_transition(conn, prev, next) do
    query!(
      conn,
      """
      INSERT INTO transitions (prev, next, n) VALUES (?1, ?2, 1)
      ON CONFLICT (prev, next) DO UPDATE SET n = transitions.n + 1
      """,
      [prev, next]
    )

    :ok
  end

  @impl Recommender.Ports.ItemSource
  def list_items(conn, limit) do
    sql = "SELECT item_id, t0, t1, t2, t3 FROM items ORDER BY item_id" <> limit_clause(limit)

    for [id, t0, t1, t2, t3] <- query!(conn, sql, []) do
      {id, [t0, t1, t2, t3]}
    end
  end

  @impl Recommender.Ports.ItemSource
  def list_transitions(conn) do
    for [prev, next, n] <- query!(conn, "SELECT prev, next, n FROM transitions", []) do
      {prev, next, n}
    end
  end

  ## Schema + statements

  defp ensure_schema(conn) do
    Sqlite3.execute(conn, """
    CREATE TABLE IF NOT EXISTS items (
      item_id TEXT PRIMARY KEY,
      t0 INTEGER NOT NULL, t1 INTEGER NOT NULL, t2 INTEGER NOT NULL, t3 INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS transitions (
      prev TEXT NOT NULL, next TEXT NOT NULL, n INTEGER NOT NULL DEFAULT 1,
      PRIMARY KEY (prev, next)
    );
    """)
  end

  defp query!(conn, sql, args) do
    {:ok, stmt} = Sqlite3.prepare(conn, sql)

    try do
      :ok = Sqlite3.bind(stmt, args)
      {:ok, rows} = Sqlite3.fetch_all(conn, stmt)
      rows
    after
      Sqlite3.release(conn, stmt)
    end
  end

  defp limit_clause(nil), do: ""
  defp limit_clause(n) when is_integer(n) and n > 0, do: " LIMIT #{n}"
end
