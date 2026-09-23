# Order-history staging decisions and business questions

## Current model purpose

`stg_order_history` prepares order-history source records for
downstream dbt models while preserving the source-file grain.

Although the source is named order history, membership in this dataset
does not by itself prove that every record was completely shipped.
Some records contain zero shipped quantity and non-zero shortage.

## Grain

Current staging grain:

> One record per row in the loaded order-history source file.

Technical source-record identity:

- `source_filename`
- `source_file_row_number`

This combination is populated and unique across the current 554,580
records.

It identifies a record within the currently loaded file version. It is
not a permanent business order-line identifier because file row numbers
can change if a file is regenerated.

## Business-key investigation

The closest business grouping investigated was:

- `company_code`
- `order_number`
- `unique_sku_code`

This combination is not unique:

- 12 combinations appear twice.
- Those groups contain 24 source records.
- Eleven pairs differ in quantities, weights, amounts, or hashes.
- One pair matches in all inspected business fields and row hash but
  has different source-file row numbers.

The identical pair is:

- Company: `zn`
- Order number: `42458`
- SKU: `SKU-BASE-00464`
- Source-file rows: `202134` and `202135`

The repeated records may represent revisions, fulfillment records,
separate source lines, or another source-system behavior. The current
data does not establish which explanation is correct.

## Confirmed staging decisions

- Preserve all 554,580 source records.
- Preserve all quantity fields without recalculation.
- Preserve shipped weight and order amount without recalculation.
- Preserve privacy-processing flags.
- Preserve file metadata and pipeline timestamps.
- Retain `row_hash` for traceability without treating it as unique.
- Rename `ingested_at_datetime` to `source_ingested_at`.
- Rename Snowflake `ingested_at` to `snowflake_loaded_at`.
- Materialize the staging model as a view.
- Do not deduplicate repeated company, order, and SKU combinations.
- Do not select a presumed latest revision.
- Do not aggregate repeated records in staging.

## Date handling

The current RAW order-history table already contains these fields as
Snowflake DATE values:

- `order_date`
- `scheduled_ship_date`
- `shipped_date`

They were converted during the earlier manual RAW refresh and are
preserved unchanged by `stg_order_history`.

This differs from the preferred architecture in which RAW preserves the
source representation and dbt staging performs type conversion. Future
loads should follow one documented contract consistently.

## Batch and processing-time distinction

The current records contain source batch:

```text
20260715_181006