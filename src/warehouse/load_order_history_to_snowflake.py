"""Load order_history from its approved S3 CSV into Snowflake.

Retain weekly rolling-window observations; replace only the selected source
file when it is retried or corrected.
The shared load_snapshot.py module explains and performs each loading step:
1. Check the local quality report and exact S3 filename.
2. Load dates as text; verify source batch counts against the local CSV.
3. Convert YYYYMMDD order/scheduled dates and padded MMDDYY shipped dates.
4. Replace that source-file partition inside a transaction; preserve older
   observations and undo changes if publication fails.

Run from the project root:
    python src/warehouse/load_order_history_to_snowflake.py
The --batch-id option selects the pseudonymization run in the filename/S3 path.
It does NOT replace the original ingestion BATCH_ID stored inside the rows.
The matching local pseudonymized CSV and quality report must both be present.
Without it, the latest date in local pseudonymized filenames is selected.
Connection settings are documented in snowflake_conn.py and docs/order_history_refresh.md.
"""
from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

# Let Python find project modules when this file is run directly by its path.
PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from src.warehouse.load_snapshot import load_dataset


def main() -> int:
    """Read the optional date, run the loader, and return a shell exit code."""
    logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")
    parser = argparse.ArgumentParser(description="Load an approved order_history snapshot.")
    parser.add_argument("--batch-id", help="Pseudonymization filename ID (YYYYMMDD_HHMMSS), not the row ingestion ID; otherwise use the latest local filename.")
    args = parser.parse_args()
    try:
        load_dataset("order_history", args.batch_id)
        return 0  # Zero tells the pipeline that this step succeeded.
    except Exception:
        logging.exception("order_history load failed")
        return 1  # Nonzero tells the pipeline to stop dependent work.


if __name__ == "__main__":
    sys.exit(main())
