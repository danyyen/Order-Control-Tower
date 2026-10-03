"""Shared loading steps for the three RAW datasets.

Think of a temporary table as a workbench: read and check the new file there
before touching the real table. A transaction then groups removal and insertion
into one change. If insertion fails, rollback restores the old rows. RAW keeps
each weekly observation; retrying one observation replaces only that partition.

Run one loader at a time per dataset. These scripts do not coordinate concurrent
writers. Validation checks counts and batch/date values, not a cryptographic
match between the local quality report and the S3 file.
"""
from __future__ import annotations

import csv
import json
from collections import Counter
import logging
import re
from datetime import datetime
from pathlib import Path
from uuid import uuid4

from config.paths import PSEUDONYMIZED_DIR, QUALITY_DIR
from src.warehouse.snowflake_conn import get_snowflake_connection

logger = logging.getLogger(__name__)

# Only these built-in names become SQL identifiers. User input is never used
# as a table name. The remaining values describe the file naming convention.
DATASETS = {
    "order_history": ("RAW.ORDER_HISTORY", "quality_report_", "batch_id"),
    "open_orders": ("RAW.OPEN_ORDERS", "quality_report_open_orders_", "batch_id"),
    "inventory": ("RAW.INVENTORY", "quality_report_inventory_", "snapshot_date"),
}


def choose_snapshot(dataset: str, requested: str | None) -> tuple[str, str, int]:
    """Choose a dated filename and check its quality report before connecting.

    Returns the batch/date identifier, expected CSV filename, and row count.
    Without a command-line date, choose the greatest date in local filenames;
    this does not mean the most recently modified file or newest file in S3.
    """
    _, report_prefix, identity_column = DATASETS[dataset]
    date_pattern = r"\d{8}" if dataset == "inventory" else r"\d{8}_\d{6}"
    filename_pattern = re.compile(rf"{dataset}_pseudonymized_({date_pattern})\.csv")
    if requested is None:
        candidates = sorted(
            path for path in PSEUDONYMIZED_DIR.glob(f"{dataset}_pseudonymized_*.csv")
            if filename_pattern.fullmatch(path.name)
        )
        if not candidates:
            raise FileNotFoundError(f"No dated {dataset} CSV found in {PSEUDONYMIZED_DIR}")
        requested = filename_pattern.fullmatch(candidates[-1].name).group(1)

    if not re.fullmatch(date_pattern, requested):
        raise ValueError("Expected YYYYMMDD for inventory or YYYYMMDD_HHMMSS for orders.")
    # strptime also rejects impossible dates such as February 30.
    datetime.strptime(requested, "%Y%m%d" if dataset == "inventory" else "%Y%m%d_%H%M%S")
    filename = f"{dataset}_pseudonymized_{requested}.csv"
    report_path = QUALITY_DIR / f"{report_prefix}{requested}.json"
    report = json.loads(report_path.read_text(encoding="utf-8-sig"))
    if report.get("overall_status") not in {"passed", "passed_with_warnings"}:
        raise ValueError(f"Quality checks did not pass: {report_path}")
    # For orders, the quality gate gets this ID from the output filename.
    # It is not necessarily the BATCH_ID stored inside each data row.
    if str(report.get(identity_column)) != requested:
        raise ValueError(f"Quality report belongs to a different batch/date: {report_path}")
    if report.get("dataset", dataset) != dataset:
        raise ValueError(f"Quality report belongs to a different dataset: {report_path}")
    count = report.get("row_count")
    # bool is a subclass of int in Python, so use type(...) is int here.
    if type(count) is not int or count <= 0:
        raise ValueError("Quality report must contain a positive integer row_count.")
    if report["overall_status"] == "passed_with_warnings":
        logger.warning("Loading a batch with quality warnings; review %s", report_path)
    return requested, filename, count



def read_source_batches(filename: str, expected: int) -> dict[str, int]:
    """Read original ingestion IDs from the selected LOCAL CSV, without changing them.

    Example: a September pseudonymization file can contain July ingestion IDs.
    Count each ID so the S3-loaded rows can be compared against the selected
    local file. This is a lineage check, not a checksum of every business value.
    """
    counts = Counter()
    with (PSEUDONYMIZED_DIR / filename).open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames or "batch_id" not in reader.fieldnames:
            raise ValueError("Selected local CSV is missing its batch_id column.")
        for row in reader:
            batch = row.get("batch_id")
            if not batch or not re.fullmatch(r"\d{8}_\d{6}(?:_\d{6})?", batch):
                raise ValueError("Selected local CSV has a missing or malformed ingestion batch_id.")
            counts[batch] += 1
    if sum(counts.values()) != expected:
        raise ValueError("Selected local CSV count differs from its quality report.")
    return dict(counts)


def prepare_order_history(cur, temporary: str, source_batches: dict[str, int]) -> str:
    """Turn the checked CSV into dated rows, like the manual Snowsight exercise.

    The input table holds dates as text. The returned temporary table holds
    actual DATE values. Both are created BEFORE the publication transaction.
    """
    validate_source_batches(cur, temporary, source_batches)

    # YY needs an explicit century rule. Here 70..99 means 1970..1999 and
    # 00..69 means 2000..2069; thus 25 and 26 mean 2025 and 2026.
    # Do not let an unrelated user/session setting silently change these dates.
    cur.execute("ALTER SESSION SET TWO_DIGIT_CENTURY_START = 1970")
    dates = {
        "ORDER_DATE": ("[0-9]{8}", "ORDER_DATE", "YYYYMMDD"),
        "SCHEDULED_SHIP_DATE": ("[0-9]{8}", "SCHEDULED_SHIP_DATE", "YYYYMMDD"),
        "SHIPPED_DATE": ("[0-9]{5,6}", "LPAD(SHIPPED_DATE, 6, '0')", "MMDDYY"),
    }
    # Reject NULLs, unexpected shapes, and impossible dates. The five/six-digit
    # check happens BEFORE LPAD, which otherwise could truncate a long value.
    checks = []
    for column, (pattern, expression, date_format) in dates.items():
        checks.append(
            f"COALESCE(COUNT_IF({column} IS NULL "
            f"OR NOT REGEXP_LIKE({column}, '{pattern}') "
            f"OR TRY_TO_DATE({expression}, '{date_format}') IS NULL), 0)"
        )
    cur.execute(f"SELECT {', '.join(checks)} FROM {temporary}")
    if any(cur.fetchone()):
        raise ValueError("Order-history dates are missing or do not match the verified date formats.")

    ready = temporary + "_READY"
    conversions = ", ".join(
        f"TO_DATE({expression}, '{date_format}') AS {column}"
        for column, (_, expression, date_format) in dates.items()
    )
    # SELECT * REPLACE changes only the three dates. Original BATCH_ID and
    # Snowflake file metadata pass through unchanged and in the same order.
    cur.execute(f"CREATE TEMPORARY TABLE {ready} AS "
                f"SELECT * REPLACE ({conversions}) FROM {temporary}")
    return ready


def validate_source_batches(cur, temporary: str, source_batches: dict[str, int]) -> None:
    """Prove S3 contains the same original ingestion batches as the local CSV."""
    cur.execute(f"SELECT BATCH_ID, COUNT(*) FROM {temporary} GROUP BY BATCH_ID")
    if dict(cur.fetchall()) != source_batches:
        raise ValueError("S3 ingestion batch IDs/counts differ from the selected local CSV.")


def replace_from_stage(conn, dataset: str, identifier: str, filename: str, expected: int,
                       source_batches: dict[str, int] | None = None) -> None:
    """Load one CSV, validate it, then publish all rows or none of them.

    The caller owns the connection and closes it. Temporary tables disappear
    when that session closes. CREATE happens before BEGIN because Snowflake
    DDL (object-definition commands) commits an active transaction.
    """
    target, _, identity_column = DATASETS[dataset]
    stage = f"@RAW.ORDER_INTELLIGENCE_S3_STAGE/{dataset}/{identity_column}={identifier}/"
    temporary = f"RAW.LOAD_CHECK_{uuid4().hex.upper()}"
    expected_identity = (
        datetime.strptime(identifier, "%Y%m%d").date()
        if dataset == "inventory" else identifier
    )
    # This function is called with a generated filename, but validate it here
    # too: FILES is SQL text and must never accept quotes or arbitrary paths.
    if not re.fullmatch(r"[a-z_]+_pseudonymized_[0-9_]+\.csv", filename):
        raise ValueError("Unexpected CSV filename")
    if not re.fullmatch(r"\d{8}" if dataset == "inventory" else r"\d{8}_\d{6}", identifier):
        raise ValueError("Unexpected batch/date identifier")

    if dataset != "inventory" and not source_batches:
        raise ValueError("Order datasets require the selected local CSV's ingestion batch counts.")

    with conn.cursor() as cur:
        # LIST proves the exact expected file exists, not just some file in
        # the folder. COPY's FILES option excludes stray or older CSVs.
        cur.execute(f"LIST {stage}")
        if not any(str(row[0]).endswith("/" + filename) for row in cur.fetchall()):
            raise FileNotFoundError(f"Expected {filename} was not found at {stage}")

        # LIKE copies the current target's column names/types without its rows.
        # Loading against those types detects conversion errors before removal.
        if dataset == "order_history":
            # The CSV stores YYYYMMDD and MMDDYY text, not SQL DATE values.
            # Mirror the workbench used in Snowsight; convert only after checks.
            cur.execute(f"""CREATE TEMPORARY TABLE {temporary} AS
                SELECT * REPLACE (
                    CAST(NULL AS VARCHAR) AS ORDER_DATE,
                    CAST(NULL AS VARCHAR) AS SCHEDULED_SHIP_DATE,
                    CAST(NULL AS VARCHAR) AS SHIPPED_DATE
                ) FROM {target} WHERE 1 = 0""")
        else:
            cur.execute(f"CREATE TEMPORARY TABLE {temporary} LIKE {target}")
        cur.execute(f"""
            COPY INTO {temporary}
            FROM {stage}
            FILES = ('{filename}')
            FILE_FORMAT = (
                FORMAT_NAME = 'RAW.ORDER_INTELLIGENCE_CSV_HEADER_FF'
                ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
            )
            MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
            INCLUDE_METADATA = (
                SOURCE_FILENAME = METADATA$FILENAME,
                SOURCE_FILE_ROW_NUMBER = METADATA$FILE_ROW_NUMBER,
                SOURCE_FILE_LAST_MODIFIED = METADATA$FILE_LAST_MODIFIED,
                INGESTED_AT = METADATA$START_SCAN_TIME
            )
            ON_ERROR = 'ABORT_STATEMENT'
        """)
        # A fresh temporary table has no previous COPY history. FORCE is not
        # needed, even when reloading the same S3 filename as a correction.
        names = [column[0].lower() for column in cur.description]
        results = [dict(zip(names, row)) for row in cur.fetchall()]
        if (len(results) != 1 or results[0].get("status") != "LOADED"
                or results[0].get("rows_loaded") != expected
                or results[0].get("errors_seen") != 0):
            raise ValueError(f"COPY did not load the expected {expected} rows: {results}")

        # Count ALL incoming rows, including invalid dates and NULLs. Checking
        # only the intended date could overlook extra rows for another date.
        # Order history's filename identifies privacy processing, whereas its
        # BATCH_ID identifies original ingestion. Compare source IDs separately.
        identity_check = (
            "BATCH_ID IS NULL" if dataset != "inventory"
            else f"{identity_column} IS NULL OR {identity_column} <> %s"
        )
        identity_params = () if dataset != "inventory" else (expected_identity,)
        cur.execute(f"""
            SELECT COUNT(*),
                COALESCE(COUNT_IF({identity_check}), 0),
                COALESCE(COUNT_IF(SOURCE_FILENAME IS NULL OR SOURCE_FILE_ROW_NUMBER IS NULL
                    OR SOURCE_FILE_LAST_MODIFIED IS NULL OR INGESTED_AT IS NULL), 0)
            FROM {temporary}
        """, identity_params)
        row_count, wrong_identity, missing_metadata = cur.fetchone()
        if row_count != expected or wrong_identity or missing_metadata:
            raise ValueError(
                f"Incoming data failed validation: rows={row_count}, "
                f"wrong batch/date={wrong_identity}, missing metadata={missing_metadata}"
            )

        publish_table = temporary
        if dataset == "order_history":
            publish_table = prepare_order_history(cur, temporary, source_batches)
        elif dataset == "open_orders":
            validate_source_batches(cur, temporary, source_batches)

        # Publish only after every incoming-data check has passed.
        # BEGIN keeps removal + insertion together even with autocommit enabled.
        cur.execute("BEGIN TRANSACTION")
        try:
            if dataset == "inventory":
                # Keep other dates. A correction replaces just this day's rows.
                cur.execute(f"DELETE FROM {target} WHERE snapshot_date = %s", (expected_identity,))
            else:
                # Keep earlier weekly observations. The source filename is the
                # publication partition, independent of the row-level BATCH_ID.
                # A retry/correction replaces only rows previously loaded from
                # this exact file, so publication is idempotent.
                cur.execute(
                    f"DELETE FROM {target} WHERE SOURCE_FILENAME = "
                    f"(SELECT MIN(SOURCE_FILENAME) FROM {temporary})"
                )
            cur.execute(f"INSERT INTO {target} SELECT * FROM {publish_table}")
            if cur.rowcount != expected:
                raise ValueError("Published row count differs from the validated incoming count.")
            conn.commit()
        except BaseException:
            # Also undo changes if the user interrupts with Ctrl+C.
            conn.rollback()
            raise
    logger.info("Published %s rows to %s for %s", expected, target, identifier)


def load_dataset(dataset: str, requested: str | None = None) -> None:
    """Connect only after local checks pass; always close the session."""
    identifier, filename, expected = choose_snapshot(dataset, requested)
    # The report/filename identify the privacy run; the CSV rows identify
    # source ingestion. Require both, rather than changing July IDs to September.
    source_batches = read_source_batches(filename, expected) if dataset != "inventory" else None
    conn = get_snowflake_connection()
    try:
        replace_from_stage(conn, dataset, identifier, filename, expected, source_batches)
    finally:
        conn.close()
