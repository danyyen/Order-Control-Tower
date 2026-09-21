"""Run a SQL file in order, stopping at the first error.

Usage: python src/warehouse/run_sql_file.py snowflake/check_connection.sql
Connection settings: see snowflake_conn.py and snowflake/README.md.

This runner executes exactly what the file contains. It does not make an
entire file atomic: earlier DDL or autocommitted changes survive a later error.
SQL files that deliberately use a transaction must include their own COMMIT.
"""
from __future__ import annotations

import argparse
import logging
import sys
from io import StringIO
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from src.warehouse.snowflake_conn import get_snowflake_connection

logger = logging.getLogger(__name__)


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")
    parser = argparse.ArgumentParser(description="Run a SQL file against Snowflake.")
    parser.add_argument("sql_file", help="Path to the SQL file, relative to this terminal's directory.")
    args = parser.parse_args()
    try:
        # utf-8-sig removes an optional Windows byte-order mark (BOM).
        # Without this, an invisible first character can cause a SQL error.
        sql_text = Path(args.sql_file).read_text(encoding="utf-8-sig")
    except OSError:
        logger.exception("Could not read %s", args.sql_file)
        return 2

    try:
        conn = get_snowflake_connection()
    except Exception:
        logger.exception("Failed to connect to Snowflake; no SQL was run")
        return 1

    completed = 0
    try:
        # The connector understands semicolons inside strings/comments.
        # execute_stream yields each completed statement instead of running
        # the entire file before returning any results.
        for cursor in conn.execute_stream(StringIO(sql_text), remove_comments=True):
            completed += 1
            try:
                logger.info("Statement %s completed (query ID: %s)", completed, cursor.sfqid)
                if cursor.description:
                    # Fetch only a small preview, not millions of rows into RAM.
                    rows = cursor.fetchmany(21)
                    names = [column[0] for column in cursor.description]
                    for row in rows[:20]:
                        logger.info("%s", dict(zip(names, row)))
                    if len(rows) > 20:
                        logger.info("More rows exist; showing the first 20 only.")
                else:
                    logger.info("Rows affected: %s", cursor.rowcount)
            finally:
                cursor.close()
        logger.info("Completed %s statement(s).", completed)
        return 0
    except KeyboardInterrupt:
        conn.rollback()
        raise
    except Exception:
        # This can undo an open transaction, but not already committed DDL.
        conn.rollback()
        logger.exception("Execution failed after %s completed statement(s).", completed)
        return 1
    finally:
        # Closing also discards temporary tables and any uncommitted work.
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
