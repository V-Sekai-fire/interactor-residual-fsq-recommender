# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Recommender.Adapters.SqlStoreTest do
  use ExUnit.Case, async: false

  alias Recommender.Adapters.SqlStore

  setup do
    dir = Path.join(System.tmp_dir!(), "rfr-sql-store-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    n = System.unique_integer([:positive])

    # With RFR_WEFTFDB_EXTENSION set, each test gets its own database in FoundationDB.
    db =
      if System.get_env("RFR_WEFTFDB_EXTENSION"),
        do: "file:rfr_test_#{n}.v1?vfs=weft_fdb",
        else: Path.join(dir, "rfr.sqlite3")

    {:ok, opts: %{data_dir: dir, db: db}}
  end

  test "an upsert replaces the item and a repeated transition counts up", %{opts: opts} do
    result =
      SqlStore.with_db(opts, fn conn ->
        :ok = SqlStore.upsert_item(conn, "a", [1, 2, 3, 4])
        :ok = SqlStore.upsert_item(conn, "a", [5, 6, 7, 8])
        :ok = SqlStore.upsert_item(conn, "b", [9, 10, 11, 12])
        :ok = SqlStore.record_transition(conn, "a", "b")
        :ok = SqlStore.record_transition(conn, "a", "b")

        {SqlStore.list_items(conn, nil), SqlStore.list_items(conn, 1),
         SqlStore.list_transitions(conn)}
      end)

    assert {[{"a", [5, 6, 7, 8]}, {"b", [9, 10, 11, 12]}], [{"a", [5, 6, 7, 8]}], [{"a", "b", 2}]} =
             result
  end

  test "rows written by one connection are read by the next", %{opts: opts} do
    SqlStore.with_db(opts, fn conn -> SqlStore.upsert_item(conn, "kept", [0, 1, 2, 3]) end)
    assert [{"kept", [0, 1, 2, 3]}] = SqlStore.with_db(opts, &SqlStore.list_items(&1, nil))
  end

  test "an extension that does not exist is an error, not a silent plain file", %{opts: opts} do
    opts = Map.put(opts, :weftfdb_extension, Path.join(opts.data_dir, "missing-weftfdb"))
    assert {:error, _} = SqlStore.with_db(opts, fn _ -> :unreachable end)
  end
end
