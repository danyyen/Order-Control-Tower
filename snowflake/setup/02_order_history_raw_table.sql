-- =========================================================
-- ORDER_HISTORY - RAW TABLE SETUP AND DATA PROFILING
-- =========================================================
-- PURPOSE: create the order-history table and inspect its data quality.
-- Run 01_project_setup.sql first so the role, schema, stage, warehouse,
-- and CSV formats exist. Your user must have the loader role.
--
-- SOURCE ASSUMPTION: each approved file is a rolling-window observation.
-- Old rows can fall out because Excel has a capacity limit; that absence is
-- not a business deletion. RAW therefore retains every weekly source file.
-- Reloading the same source filename replaces only that file's rows.
-- Recurring loads are handled by src/warehouse/load_order_history_to_snowflake.py.
--
-- GRAIN means what one row represents: here, one ERP order-line record.
-- ERP means the source business system used to manage orders and inventory.
-- No reliable unique order-line key has been established yet. Profiling
-- below checks possible keys; it does not declare or enforce a primary key.
-- Previously reported duplicate counts are observations, not guarantees
-- about the current data. Run the queries to measure the current snapshot.
--
-- Running this file creates the table if missing and runs read-only checks.
-- Section 3 is a COMMENTED example: it will not load or delete data as written.

USE ROLE ORDER_INTELLIGENCE_LOADER;
USE DATABASE ORDER_INTELLIGENCE_DB;
USE SCHEMA RAW;
USE WAREHOUSE ORDER_INTELLIGENCE_WH;

-- =========================================================
-- 1. CREATE THE TABLE AND DEFINE ITS COLUMNS
-- =========================================================
-- DDL means data definition language: SQL that defines objects like tables.
-- IF NOT EXISTS preserves an existing table and its rows. It does not
-- add missing columns or correct existing types; use ALTER TABLE for that.
-- CREATE OR REPLACE would replace the table, so avoid it for routine setup.
--
-- These are the project's proposed column types. Compare them with the
-- actual CSV and existing table before loading, especially decimal quantities.
-- All columns below allow NULL because no NOT NULL constraint is specified.
-- Unquoted names such as order_number are stored as uppercase in Snowflake.
--
-- Optional schema discovery (INFER_SCHEMA guesses names/types from files):
-- replace <BATCH_ID> with one approved batch before running this example.
-- SELECT * FROM TABLE(INFER_SCHEMA(
--     LOCATION => '@ORDER_INTELLIGENCE_S3_STAGE/order_history/batch_id=<BATCH_ID>/',
--     FILE_FORMAT => 'ORDER_INTELLIGENCE_CSV_HEADER_FF',
--     IGNORE_CASE => TRUE
-- ));
-- Inference helps compare schemas; it does not prove every value will fit.

CREATE TABLE IF NOT EXISTS RAW.ORDER_HISTORY (
    -- VARCHAR stores text, including codes with leading zeros.
    -- Selected identifying fields are replaced upstream by src/privacy/.
    company_code                                VARCHAR,
    order_number                                VARCHAR,
    purchase_order_number                       VARCHAR,
    customer_name                               VARCHAR,
    delivery_route                              VARCHAR,
    order_type                                  VARCHAR,
    order_status                                VARCHAR,
    full_sku_code                               VARCHAR,
    first_half_sku_code                         VARCHAR,
    unique_sku_code                             VARCHAR,
    product_description                         VARCHAR,
    product_category                            VARCHAR,
    batch_id                                    VARCHAR,

    -- DATE stores a calendar date without a time of day.
    order_date                                  DATE,
    scheduled_ship_date                         DATE,
    shipped_date                                DATE,

    -- NUMBER without a scale means NUMBER(38, 0): no decimal places.
    -- Confirm quantities are whole units; fractional quantities need a scale.
    -- NUMBER(18, 4) allows 18 total digits, including 4 after the decimal.
    ordered_quantity                            NUMBER,
    secondary_order_quantity                    NUMBER,
    final_order_quantity                        NUMBER,
    shipped_order_quantity                      NUMBER,
    quantity_short                              NUMBER,
    shipped_order_weight                        NUMBER(18, 4),
    order_amount                                NUMBER(18, 4),

    -- BOOLEAN stores TRUE, FALSE, or NULL (unknown/missing).
    -- These flags report upstream removal/replacement of original fields.
    original_product_description_removed        BOOLEAN,
    original_product_category_removed            BOOLEAN,
    original_customer_name_removed                BOOLEAN,
    original_sku_codes_removed                    BOOLEAN,
    original_purchase_order_number_removed        BOOLEAN,
    original_company_code_removed                 BOOLEAN,

    -- Audit fields describe what the Python pipeline did and when.
    -- row_hash is a 32-character fingerprint of selected source fields.
    -- TIMESTAMP_NTZ stores date/time without time-zone information.
    row_hash                                    VARCHAR(32),
    ingested_at_datetime                        TIMESTAMP_NTZ,
    standardized_at                             TIMESTAMP_NTZ,
    pseudonymized_at                            TIMESTAMP_NTZ,

    -- Lineage means tracing a row back to its source file and load.
    -- COPY supplies these four fields; they are not ordinary CSV fields.
    -- TIMESTAMP_LTZ stores an instant, displayed in the session time zone.
    -- ingested_at records the Snowflake scan start, not the Python run time.
    source_filename                             VARCHAR,
    source_file_row_number                      NUMBER,
    source_file_last_modified                   TIMESTAMP_NTZ,
    ingested_at                                 TIMESTAMP_LTZ
);


-- =========================================================
-- 2. CHECK THE TABLE STRUCTURE
-- =========================================================
-- DESCRIBE displays column names, types, and other column settings.
DESCRIBE TABLE RAW.ORDER_HISTORY;

-- INFORMATION_SCHEMA is Snowflake's catalog of database objects.
-- WHERE selects this table; ORDINAL_POSITION preserves column order.
SELECT COLUMN_NAME, DATA_TYPE, NUMERIC_PRECISION, NUMERIC_SCALE
FROM ORDER_INTELLIGENCE_DB.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'RAW'
  AND TABLE_NAME = 'ORDER_HISTORY'
ORDER BY ORDINAL_POSITION;

-- =========================================================
-- 3. OPTIONAL MANUAL FIRST LOAD - EXAMPLE ONLY
-- =========================================================
-- Prefer the project's Python loader for normal loads.
-- To use this example, select an approved batch and replace <BATCH_ID>.
-- Keep only the intended CSV data files in the selected batch location.
-- Run the statements deliberately in order, not as an unattended script.
--
-- Delete only the exact source filename being retried. Never truncate this
-- table: doing so would lose orders that fell outside Excel's rolling window.
-- The explicit transaction below lets you roll back a partition replacement, but
-- YOU must inspect the results before choosing COMMIT or ROLLBACK.
-- A COPY that finds no files can finish without an error and load zero rows.
--
-- The block comment markers below keep this entire example inactive.
/*
-- First confirm the exact source files exist. @ refers to the named stage.
LIST @ORDER_INTELLIGENCE_S3_STAGE/order_history/batch_id=<BATCH_ID>/;

BEGIN TRANSACTION;
DELETE FROM RAW.ORDER_HISTORY
WHERE source_filename = 'order_history/batch_id=<BATCH_ID>/order_history_pseudonymized_<BATCH_ID>.csv';

-- COPY INTO reads staged files and inserts their rows into the table.
COPY INTO RAW.ORDER_HISTORY
FROM @ORDER_INTELLIGENCE_S3_STAGE/order_history/batch_id=<BATCH_ID>/
FILE_FORMAT = (
    -- This saved format reads CSV headers as column names.
    FORMAT_NAME = 'ORDER_INTELLIGENCE_CSV_HEADER_FF'
    -- Required for CSV with INCLUDE_METADATA: the table has extra fields.
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
)
-- Match header names regardless of upper/lowercase; column order may differ.
-- Extra file columns can be ignored and absent table columns can become NULL.
-- Consequently, a successful COPY alone does not prove the schema is correct.
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
-- Map Snowflake's file metadata into the four existing audit columns.
INCLUDE_METADATA = (
    SOURCE_FILENAME = METADATA$FILENAME,
    SOURCE_FILE_ROW_NUMBER = METADATA$FILE_ROW_NUMBER,
    SOURCE_FILE_LAST_MODIFIED = METADATA$FILE_LAST_MODIFIED,
    INGESTED_AT = METADATA$START_SCAN_TIME
)
ON_ERROR = 'ABORT_STATEMENT'; -- Fail this COPY if a data-loading error occurs.

-- Inspect COPY's result for files loaded, row counts, and errors.
-- Compare these totals and batch values with the approved source.
SELECT source_filename, batch_id, COUNT(*) AS row_count
FROM RAW.ORDER_HISTORY
GROUP BY source_filename, batch_id;

-- Execute exactly ONE of these after inspection, in the same session:
-- COMMIT;   -- Keep the replacement only when the expected data loaded.
-- ROLLBACK; -- Restore the previous rows if COPY failed or checks disagree.
-- Do not leave the transaction open or run DDL while inspecting it.
*/

-- This read-only summary also works after a load through the Python script.
-- COUNT(*) counts rows. GROUP BY produces one result for each source file.
SELECT source_filename, COUNT(*) AS row_count
FROM RAW.ORDER_HISTORY
GROUP BY source_filename;

-- =========================================================
-- 4. CHECK POSSIBLE BUSINESS KEYS AND DUPLICATES
-- =========================================================
-- A business key identifies the same logical record across snapshots.
-- A candidate key is a combination we are testing for that purpose.
-- Here we test company_code + order_number + unique_sku_code.
--
-- DISTINCT removes repeated combinations. This counts actual column
-- combinations without joining them into text, avoiding separator collisions.
-- It also includes combinations containing NULL; missing values are checked
-- separately below because a useful key must be reliably populated.
SELECT
    (SELECT COUNT(*) FROM RAW.ORDER_HISTORY) AS total_rows,
    (SELECT COUNT(*) FROM (
        SELECT DISTINCT company_code, order_number, unique_sku_code
        FROM RAW.ORDER_HISTORY
    ) AS candidate_keys) AS distinct_candidate_keys;
-- If the counts differ, at least one combination repeats.
-- Matching counts only establish uniqueness in this snapshot, not over time.

-- GROUP BY combines matching keys. HAVING filters the grouped results.
-- More than one row in a group means that candidate key is repeated.
SELECT
    company_code, order_number, unique_sku_code,
    COUNT(*) AS row_count
FROM RAW.ORDER_HISTORY
GROUP BY company_code, order_number, unique_sku_code
HAVING COUNT(*) > 1
ORDER BY row_count DESC; -- Show the largest repeated groups first.

-- Show all original rows belonging to repeated groups, including NULL keys.
-- OVER/PARTITION BY counts each group without collapsing its individual rows.
-- QUALIFY filters after that window calculation has been evaluated.
-- Compare these rows to distinguish repeated lines from exact duplicates.
SELECT *
FROM RAW.ORDER_HISTORY
QUALIFY COUNT(*) OVER (
    PARTITION BY company_code, order_number, unique_sku_code
) > 1
ORDER BY company_code, order_number, unique_sku_code;

-- COUNT_IF counts rows satisfying a condition; IS NULL tests missing data.
-- COALESCE converts a NULL count into 0 for an easy-to-read summary.
-- These checks do not detect blank strings or other invalid codes.
SELECT
    COALESCE(COUNT_IF(company_code IS NULL), 0) AS null_company_code,
    COALESCE(COUNT_IF(order_number IS NULL), 0) AS null_order_number,
    COALESCE(COUNT_IF(unique_sku_code IS NULL), 0) AS null_unique_sku_code
FROM RAW.ORDER_HISTORY;

-- A row hash is a fingerprint of selected values used by the Python pipeline.
-- It is not an order-line ID. Matching hashes are a reason to inspect rows:
-- fields excluded from the hash can differ, and hash collisions are possible.
SELECT row_hash, COUNT(*) AS row_count
FROM RAW.ORDER_HISTORY
GROUP BY row_hash
HAVING COUNT(*) > 1
ORDER BY row_count DESC;

-- COUNT(DISTINCT ...) ignores NULL, so show missing hashes separately.
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT row_hash) AS distinct_row_hashes,
    COALESCE(COUNT_IF(row_hash IS NULL), 0) AS null_row_hashes
FROM RAW.ORDER_HISTORY;

-- Test another possible key. LIMIT 20 shows only a sample of repeated groups.
-- Even if no groups repeat, verify that the fields identify the same order
-- line over time. Do not add changing quantities/prices just to force uniqueness.
SELECT order_number, purchase_order_number, full_sku_code, COUNT(*) AS row_count
FROM RAW.ORDER_HISTORY
GROUP BY order_number, purchase_order_number, full_sku_code
HAVING COUNT(*) > 1
ORDER BY row_count DESC
LIMIT 20;

-- =========================================================
-- 5. OPTIONAL: NUMBER ROWS WITHIN EACH ORDER/SKU GROUP
-- =========================================================
-- ROW_NUMBER labels rows 1, 2, 3... within each PARTITION BY group.
-- ORDER BY chooses their sequence; the filename distinguishes multiple files.
-- If ordering values tie, their relative numbering is not guaranteed.
-- This SELECT does not save the generated column into the table.
-- File positions can change between snapshots, so this is an investigation
-- aid, not a permanent order-line key.
/*
SELECT *,
    ROW_NUMBER() OVER (
        PARTITION BY company_code, order_number, purchase_order_number, full_sku_code
        ORDER BY source_filename, source_file_row_number
    ) AS line_sequence
FROM RAW.ORDER_HISTORY;
*/
