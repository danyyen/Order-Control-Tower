"""Offline regression checks: failed loads must preserve the published rows.

The fake session models transaction commit/rollback. No credentials, network,
S3 objects, or real Snowflake tables are used by these tests.
"""
import copy
import json
from datetime import date

import pytest

from src.warehouse import load_snapshot as loader


class Session:
    def __init__(self, dataset, failure=None):
        self.dataset = dataset
        self.failure = failure
        current = ("2026-07-10" if dataset == "inventory"
                   else f"path/{dataset}_pseudonymized_20260710_010203.csv")
        earlier = ("2026-07-09" if dataset == "inventory"
                   else f"path/{dataset}_pseudonymized_20260703_010203.csv")
        # Same logical SKU/pallet can have different facts in two observations.
        self.rows = [("same-sku-pallet", current, 10),
                     ("same-sku-pallet", earlier, 7)]
        self.original = copy.deepcopy(self.rows)
        self.pending = None
        self.commits = 0
        self.rollbacks = 0
        self.commands = []
        self.filename = f"{dataset}_pseudonymized_{'20260710' if dataset == 'inventory' else '20260710_010203'}.csv"
        self.description = None
        self.rowcount = 0
        self.result = []

    def cursor(self):
        return self

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass

    def execute(self, sql, params=None):
        sql = " ".join(sql.split())
        self.commands.append(sql)
        if sql.startswith("LIST"):
            self.result = [] if self.failure == "missing_file" else [("s3://bucket/path/" + self.filename,)]
        elif sql.startswith("COPY"):
            if self.failure == "copy_error":
                raise RuntimeError("bad CSV")
            assert f"FILES = ('{self.filename}')" in sql
            self.description = [(name,) for name in ("status", "rows_loaded", "errors_seen")]
            self.result = [("LOAD_SKIPPED" if self.failure == "skipped" else "LOADED", 2, 0)]
        elif sql.startswith("SELECT BATCH_ID, COUNT(*)"):
            self.result = [("wrong" if self.failure == "source_batch" else "20260715_181006", 2)]
        elif sql.startswith("SELECT COALESCE(COUNT_IF(ORDER_DATE"):
            self.result = [(1 if self.failure == "date" else 0, 0, 0)]
        elif sql.startswith("CREATE TEMPORARY") and "_READY AS" in sql:
            if self.failure == "conversion":
                raise ValueError("date conversion failed")
        elif sql.startswith("SELECT COUNT(*)"):
            self.result = [(1 if self.failure == "count" else 2,
                            1 if self.failure == "identity" else 0,
                            1 if self.failure == "metadata" else 0)]
        elif sql == "BEGIN TRANSACTION":
            self.pending = copy.deepcopy(self.rows)
        elif sql.startswith("DELETE"):
            if self.dataset == "inventory":
                assert params == (date(2026, 7, 10),)
                partition = "2026-07-10"
            else:
                assert params is None
                assert "SOURCE_FILENAME = (SELECT MIN(SOURCE_FILENAME)" in sql
                partition = "path/" + self.filename
            self.pending = [row for row in self.pending if row[1] != partition]
        elif sql.startswith("INSERT"):
            partition = ("2026-07-10" if self.dataset == "inventory"
                         else "path/" + self.filename)
            self.pending.extend([("same-sku-pallet", partition, 12),
                                 ("second-row", partition, 4)])
            if self.failure == "insert":
                raise RuntimeError("insert failed")
            if self.failure == "interrupt":
                raise KeyboardInterrupt()
            self.rowcount = 1 if self.failure == "insert_count" else 2
        return self

    def fetchall(self):
        return self.result

    def fetchone(self):
        return self.result[0]

    def commit(self):
        self.rows = self.pending
        self.commits += 1

    def rollback(self):
        self.pending = None
        self.rollbacks += 1


def run_load(session):
    identifier = "20260710" if session.dataset == "inventory" else "20260710_010203"
    loader.replace_from_stage(session, session.dataset, identifier, session.filename, 2,
                              {"20260715_181006": 2} if session.dataset != "inventory" else None)


@pytest.mark.parametrize("dataset", loader.DATASETS)
def test_success_replaces_only_intended_rows(dataset):
    session = Session(dataset)
    run_load(session)
    assert session.commits == 1
    assert session.rollbacks == 0
    current = ("2026-07-10" if dataset == "inventory"
               else f"path/{dataset}_pseudonymized_20260710_010203.csv")
    earlier = ("2026-07-09" if dataset == "inventory"
               else f"path/{dataset}_pseudonymized_20260703_010203.csv")
    assert ("same-sku-pallet", current, 10) not in session.rows
    assert ("same-sku-pallet", current, 12) in session.rows
    assert ("same-sku-pallet", earlier, 7) in session.rows
    assert len(session.rows) == 3


def test_inventory_retains_changed_facts_for_same_sku_pallet_across_dates():
    session = Session("inventory")
    run_load(session)
    observations = [row for row in session.rows if row[0] == "same-sku-pallet"]
    assert observations == [
        ("same-sku-pallet", "2026-07-09", 7),
        ("same-sku-pallet", "2026-07-10", 12),
    ]


@pytest.mark.parametrize("dataset", ["order_history", "open_orders"])
def test_order_observations_are_appended_and_same_file_reload_is_idempotent(dataset):
    session = Session(dataset)
    run_load(session)
    run_load(session)
    assert len(session.rows) == 3
    assert not any(command.startswith("TRUNCATE") for command in session.commands)


@pytest.mark.parametrize("dataset", loader.DATASETS)
@pytest.mark.parametrize("failure", ["missing_file", "copy_error", "skipped", "count", "identity", "metadata"])
def test_invalid_incoming_data_never_touches_target(dataset, failure):
    session = Session(dataset, failure)
    with pytest.raises((RuntimeError, ValueError, FileNotFoundError)):
        run_load(session)
    assert session.rows == session.original
    assert "BEGIN TRANSACTION" not in session.commands
    assert session.commits == 0


@pytest.mark.parametrize("dataset", loader.DATASETS)
@pytest.mark.parametrize("failure", ["insert", "insert_count", "interrupt"])
def test_failed_publication_rolls_back_removal(dataset, failure):
    session = Session(dataset, failure)
    with pytest.raises((RuntimeError, ValueError, KeyboardInterrupt)):
        run_load(session)
    assert session.rows == session.original
    assert session.rollbacks == 1
    assert session.commits == 0


@pytest.mark.parametrize("count", [None, True, "2", -1, 0])
def test_bad_quality_counts_rejected_before_connection(tmp_path, monkeypatch, count):
    monkeypatch.setattr(loader, "QUALITY_DIR", tmp_path)
    report = {"overall_status": "passed", "batch_id": "20260710_010203", "row_count": count}
    (tmp_path / "quality_report_20260710_010203.json").write_text(json.dumps(report))
    with pytest.raises(ValueError, match="row_count"):
        loader.choose_snapshot("order_history", "20260710_010203")


def test_mismatched_report_rejected(tmp_path, monkeypatch):
    monkeypatch.setattr(loader, "QUALITY_DIR", tmp_path)
    report = {"overall_status": "passed", "batch_id": "20260711_010203", "row_count": 2}
    (tmp_path / "quality_report_20260710_010203.json").write_text(json.dumps(report))
    with pytest.raises(ValueError, match="different batch"):
        loader.choose_snapshot("order_history", "20260710_010203")


def test_invalid_calendar_date_rejected():
    with pytest.raises(ValueError):
        loader.choose_snapshot("inventory", "20260230")


def test_connection_closed_on_load_failure(monkeypatch):
    class Connection:
        closed = False
        def close(self):
            self.closed = True
    conn = Connection()
    monkeypatch.setattr(loader, "choose_snapshot", lambda *args: ("20260710", "x.csv", 2))
    monkeypatch.setattr(loader, "get_snowflake_connection", lambda: conn)
    def fail(*args):
        raise ValueError("invalid data")
    monkeypatch.setattr(loader, "replace_from_stage", fail)
    with pytest.raises(ValueError):
        loader.load_dataset("inventory")
    assert conn.closed


@pytest.mark.parametrize("failure", ["source_batch", "date", "conversion"])
def test_order_history_lineage_or_date_failure_prevents_publication(failure):
    session = Session("order_history", failure)
    with pytest.raises(ValueError):
        run_load(session)
    assert session.rows == session.original
    assert "BEGIN TRANSACTION" not in session.commands
    assert session.commits == 0


def test_order_history_dates_converted_before_transaction_and_batch_preserved():
    session = Session("order_history")
    run_load(session)
    commands = session.commands
    raw_create = next(s for s in commands if s.startswith("CREATE TEMPORARY") and "WHERE 1 = 0" in s)
    assert "CAST(NULL AS VARCHAR) AS ORDER_DATE" in raw_create
    ready_create = next(s for s in commands if s.startswith("CREATE TEMPORARY") and "_READY AS" in s)
    assert "TO_DATE(ORDER_DATE, 'YYYYMMDD')" in ready_create
    assert "TO_DATE(SCHEDULED_SHIP_DATE, 'YYYYMMDD')" in ready_create
    assert "TO_DATE(LPAD(SHIPPED_DATE, 6, '0'), 'MMDDYY')" in ready_create
    assert "BATCH_ID" not in ready_create  # The conversion must not overwrite it.
    assert commands.index(ready_create) < commands.index("BEGIN TRANSACTION")
    assert "ALTER SESSION SET TWO_DIGIT_CENTURY_START = 1970" in commands
    assert next(s for s in commands if s.startswith("INSERT")).endswith("_READY")


def test_local_csv_preserves_older_ingestion_id(tmp_path, monkeypatch):
    monkeypatch.setattr(loader, "PSEUDONYMIZED_DIR", tmp_path)
    filename = "order_history_pseudonymized_20260915_032626.csv"
    (tmp_path / filename).write_text(
        "batch_id,order_date\n20260715_181006,20260615\n20260715_181006,20260616\n",
        encoding="utf-8-sig",
    )
    assert loader.read_source_batches(filename, 2) == {"20260715_181006": 2}


@pytest.mark.parametrize("contents, expected", [
    ("batch_id\n20260715_181006\n", 2),
    ("other_column\nvalue\n", 1),
    ("batch_id\nNULL\n", 1),
])
def test_local_csv_invalid_lineage_or_count_rejected(tmp_path, monkeypatch, contents, expected):
    monkeypatch.setattr(loader, "PSEUDONYMIZED_DIR", tmp_path)
    (tmp_path / "selected.csv").write_text(contents, encoding="utf-8")
    with pytest.raises(ValueError):
        loader.read_source_batches("selected.csv", expected)
