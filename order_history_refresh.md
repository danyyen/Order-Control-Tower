# Order history: the refresh we learned in Snowsight

## What happened

The user inspected and refreshed ORDER_HISTORY manually. The September file
contained 554,580 rows originally ingested in July. It was processed for privacy
in September. The user reported matching verification results and committed the
replacement in Snowsight. That refresh did not require recreating the RAW table.

| Identifier | Example | Meaning |
| --- | --- | --- |
| Row BATCH_ID | 20260715_181006 | Original source ingestion |
| Filename/S3 batch_id | 20260915_032626 | Pseudonymization output run |
| PSEUDONYMIZED_AT | 2026-09-15 03:26:45.427 | When privacy processing happened |
| INGESTED_AT | Filled by Snowflake COPY | When Snowflake scanned the file |

A newer filename does not require changing the original ingestion ID. The
quality report's batch_id is derived from the output filename, so it describes
the privacy run rather than the batch_id values inside the CSV.

## How Python now follows the manual exercise

1. Choose the approved privacy-run filename and matching passing quality report.
2. Read ingestion batch IDs and their counts from that exact local CSV.
3. Load the exact S3 CSV into a temporary checking table, with date columns as text.
4. Compare row counts, source ingestion IDs/counts, and load metadata.
5. Reject missing/invalid dates, then create a second temporary table with real dates.
6. Begin a transaction, delete only rows from that exact source filename,
   insert the prepared rows, and commit. Earlier weekly observations remain.
7. Roll back a failed publication and close the session, removing temporary tables.

These steps live in src/warehouse/load_snapshot.py. The short
src/warehouse/load_order_history_to_snowflake.py file handles command-line input.
Open orders uses the same source-file partition rule so weekly backlog snapshots
remain available. Inventory replaces only the selected snapshot date, allowing
the same SKU/pallet to carry different quantities on different dates.

## Date rules confirmed in the file

| Field | File example | Rule | Stored date |
| --- | --- | --- | --- |
| ORDER_DATE | 20260615 | YYYYMMDD | 2026-06-15 |
| SCHEDULED_SHIP_DATE | 20260616 | YYYYMMDD | 2026-06-16 |
| SHIPPED_DATE | 61626 | Pad to 061626, then MMDDYY | 2026-06-16 |

Order/scheduled dates must contain exactly eight digits. Shipped dates must
contain five or six digits before padding, so long unexpected values cannot be
silently cut off. NULL or impossible dates stop the load before RAW changes.
The fresh loader session explicitly sets TWO_DIGIT_CENTURY_START to 1970:
70-99 represent 1970-1999, and 00-69 represent 2000-2069. This makes 25/26 mean
2025/2026 regardless of the user's session defaults. Revisit this rule if the
source ever requires a different century. The verified file's shipped dates
ranged from 2025-06-06 through 2026-07-09; that range is not hardcoded as a rule.

## Future runs

No need to reload the batch just committed manually. For a future deliberate
rerun, set the terminal credentials as described in snowflake_conn.py, supply a
fresh TOTP, and run from the project root:

```powershell
python src/warehouse/load_order_history_to_snowflake.py --batch-id 20260915_032626
```

Here --batch-id means the identifier in the filename, not the source ingestion
ID inside the rows. Both the selected local pseudonymized CSV and quality report
must exist, as must the exact CSV in S3. Missing local CSVs stop the load rather
than weakening the lineage check. Run one writer at a time for this dataset.

The automated lineage comparison is not a checksum of all business values.
Date parsing does not prove business correctness, and metadata does not prove
pseudonymization. Keep the upstream privacy/quality checks. Offline tests cover
the control flow; only a live run can verify the complete Snowflake execution.
