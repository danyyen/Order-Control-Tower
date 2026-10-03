"""Load inventory from its approved S3 CSV into Snowflake.

Keep earlier inventory dates; replace only the selected date.
The shared load_snapshot.py module explains and performs each loading step:
1. Check the local quality report and exact S3 filename.
2. Load a temporary table and validate its count, batch/date, and metadata.
3. Publish inside a transaction; undo changes if publication fails.

Run from the project root:
    python src/warehouse/load_inventory_to_snowflake.py
Add --snapshot-date to select an earlier approved batch/date deliberately.
Without it, the latest date in local pseudonymized filenames is selected.
Connection settings are documented in snowflake_conn.py and snowflake/README.md.
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
    parser = argparse.ArgumentParser(description="Load an approved inventory snapshot.")
    parser.add_argument("--snapshot-date", help="Explicit YYYYMMDD identifier; otherwise use the latest local filename.")
    args = parser.parse_args()
    try:
        load_dataset("inventory", args.snapshot_date)
        return 0  # Zero tells the pipeline that this step succeeded.
    except Exception:
        logging.exception("inventory load failed")
        return 1  # Nonzero tells the pipeline to stop dependent work.


if __name__ == "__main__":
    sys.exit(main())
