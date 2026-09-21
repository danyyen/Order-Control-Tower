-- THIS SCRIPT WAS CREATED AFTER NOTICING SOME COLUMNS THAT NEEDED ADDITIONAL PSEUDONYMIZATION
-- IT TEACHES AND APPLIES HOW TO APPLY UPDATED PSEUDONYMIZED FILE TO STAGING THEN TO RAW IN SNOWFLAKE
-- ESPECIALLY WHEN YOU WANT TO REPLACE OLD FILE.

--- inspect RAW → find the S3 file → compare and validate → refresh.


-- ============================================================================
-- ORDER HISTORY: UNDERSTAND, CHECK, AND REFRESH RAW DATA
-- ============================================================================
-- PURPOSE
-- Save the manual Snowsight exercise as a learning reference.
-- This is a historical worked example for the September 15, 2026 file.
-- You already completed that refresh; reading this file does not require
-- repeating the load. For another batch, review the filename and expectations.
--
-- THE DATA PATH
-- S3 CSV -> temporary CHECK table -> temporary READY table -> real RAW table
-- A Snowflake stage is a named pointer to the S3 files, not another data copy.
-- Snowsight and local Python scripts both send SQL to the same cloud Snowflake.
--
-- TWO DIFFERENT IDS (the most important discovery in this exercise)
--   Row BATCH_ID:         20260715_181006 = original source ingestion.
--   Filename/folder ID:   20260915_032626 = later pseudonymization output run.
-- Reprocessing July data in September does not change its original ingestion ID.
-- Never require those two IDs to match or overwrite one merely to match the other.
--
-- EXPECTATIONS RECORDED FOR THIS FILE
--   Rows: 554580. Source ingestion batches: 1.
--   PSEUDONYMIZED_AT: 2026-09-15 03:26:45.427.
--   Parsed shipped dates: 2025-06-06 through 2026-07-09.
-- These are observations about this file, not fixed rules for future batches.
--
-- HOW TO USE THIS WALKTHROUGH
-- Run one numbered section at a time in the SAME Snowsight worksheet/session.
-- Read its WHY and INTERPRET comments, then inspect the result before proceeding.
-- Temporary tables disappear when the session ends. If a temporary table name
-- already exists, continue from the completed step or start a fresh session.
-- The actual RAW replacement in section 9 is commented out intentionally:
-- select its statements manually only when you intend to publish checked data.
-- Do not run this entire file through the generic Python SQL runner.

-- ============================================================================
-- 1. CHOOSE THE SESSION CONTEXT
-- ============================================================================
-- WHY: short names such as RAW.ORDER_HISTORY need a database, and queries need
-- a role with permission and a warehouse providing computing power.
USE ROLE ORDER_INTELLIGENCE_LOADER;
USE DATABASE ORDER_INTELLIGENCE_DB;
USE SCHEMA RAW;
USE WAREHOUSE ORDER_INTELLIGENCE_WH;

-- Make the meaning of two-digit years explicit for this session.
-- With this setting, 70-99 mean 1970-1999 and 00-69 mean 2000-2069.
-- Our shipped years 25 and 26 therefore become 2025 and 2026.
ALTER SESSION SET TWO_DIGIT_CENTURY_START = 1970;

-- ============================================================================
-- 2. INSPECT THE EXISTING RAW TABLE
-- ============================================================================
-- WHY: check the real column names/types before designing a replacement.
-- INTERPRET: DATE columns need real dates; VARCHAR stores text; NUMBER(p,s)
-- means p total digits, with s digits after the decimal point.
DESCRIBE TABLE RAW.ORDER_HISTORY;

-- WHY: establish what is already loaded before making any changes.
-- GROUP BY produces one summary row per source-batch/file combination.
-- COUNT(*) counts rows; MAX returns the latest recorded scan time.
SELECT
    batch_id,
    source_filename,
    COUNT(*) AS row_count,
    MAX(ingested_at) AS latest_load_scan_time
FROM RAW.ORDER_HISTORY
GROUP BY batch_id, source_filename;
-- INTERPRET: originally we saw 554580 July-batch rows with NULL metadata.
-- NULL metadata meant the file/load time was unrecorded, not proof that those
-- rows were old. After the refresh, this query should show the September path.

-- ============================================================================
-- 3. LOCATE THE S3 FILE AND COMPARE ITS COLUMNS
-- ============================================================================
-- WHY: uploading a newer CSV to S3 does not automatically update RAW.
-- LIST shows available files. It does not load their rows into a table.
LIST @ORDER_INTELLIGENCE_S3_STAGE/order_history/;

-- WHY: inspect the selected CSV's column names and guessed types.
-- INFER_SCHEMA discovers structure; it does not alter RAW.
-- FILES selects one exact file, avoiding accidental inspection of other batches.
SELECT COLUMN_NAME, TYPE, ORDER_ID
FROM TABLE(INFER_SCHEMA(
    LOCATION => '@ORDER_INTELLIGENCE_S3_STAGE/order_history/batch_id=20260915_032626/',
    FILES => ('order_history_pseudonymized_20260915_032626.csv'),
    FILE_FORMAT => 'ORDER_INTELLIGENCE_CSV_HEADER_FF',
    IGNORE_CASE => TRUE
))
ORDER BY ORDER_ID;
-- INTERPRET: all 33 CSV columns existed in RAW; RAW had four extra metadata
-- columns. Different column order is fine because COPY below matches names.
-- Numeric-looking codes can remain VARCHAR to preserve their representation.
-- The inferred numeric date fields prompted the date investigation below.

-- ============================================================================
-- 4. LOAD A TEMPORARY CHECKING TABLE, KEEPING DATES AS TEXT
-- ============================================================================
-- WHY: inspect the incoming rows without changing the real RAW data.
-- AS SELECT builds a table from the query's structure.
-- SELECT * REPLACE changes the three date expressions in the NEW table only.
-- WHERE 1 = 0 is always false: copy the structure, but zero existing rows.
CREATE TEMPORARY TABLE RAW.ORDER_HISTORY_REFRESH_CHECK AS
SELECT * REPLACE (
    CAST(NULL AS VARCHAR) AS ORDER_DATE,
    CAST(NULL AS VARCHAR) AS SCHEDULED_SHIP_DATE,
    CAST(NULL AS VARCHAR) AS SHIPPED_DATE
)
FROM RAW.ORDER_HISTORY
WHERE 1 = 0;

-- COPY reads the CSV into the checking table, not the real RAW table.
COPY INTO RAW.ORDER_HISTORY_REFRESH_CHECK
FROM @ORDER_INTELLIGENCE_S3_STAGE/order_history/batch_id=20260915_032626/
FILES = ('order_history_pseudonymized_20260915_032626.csv')
FILE_FORMAT = (
    FORMAT_NAME = 'ORDER_INTELLIGENCE_CSV_HEADER_FF'
    -- Required when adding file metadata to CSV rows.
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
)
-- Header names decide the destination columns; capitalization is ignored.
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
-- Metadata lets us trace each loaded row back to its file and scan time.
INCLUDE_METADATA = (
    SOURCE_FILENAME = METADATA$FILENAME,
    SOURCE_FILE_ROW_NUMBER = METADATA$FILE_ROW_NUMBER,
    SOURCE_FILE_LAST_MODIFIED = METADATA$FILE_LAST_MODIFIED,
    INGESTED_AT = METADATA$START_SCAN_TIME
)
ON_ERROR = 'ABORT_STATEMENT';
-- INTERPRET: expect LOADED, ROWS_PARSED = ROWS_LOADED = 554580, ERRORS_SEEN = 0.
-- Stop if the result differs. No real RAW rows have changed.
-- Name matching is not a full schema check: extra CSV columns can be ignored.

-- ============================================================================
-- 5. PREVIEW THE DATE INTERPRETATION
-- ============================================================================
-- WHY: dates were encoded differently in the source file.
--   20260615 -> YYYYMMDD -> 2026-06-15
--   61626 -> pad to 061626 -> MMDDYY -> 2026-06-16
-- LPAD adds a leading zero. TRY_TO_DATE returns NULL if conversion fails.
-- DISTINCT removes repeated examples; LIMIT bounds the displayed sample.
SELECT DISTINCT
    order_date AS original_order_date,
    TRY_TO_DATE(order_date, 'YYYYMMDD') AS parsed_order_date,
    scheduled_ship_date AS original_scheduled_date,
    TRY_TO_DATE(scheduled_ship_date, 'YYYYMMDD') AS parsed_scheduled_date,
    shipped_date AS original_shipped_date,
    CASE WHEN REGEXP_LIKE(shipped_date, '[0-9]{5,6}')
        THEN TRY_TO_DATE(LPAD(shipped_date, 6, '0'), 'MMDDYY')
    END AS parsed_shipped_date
FROM RAW.ORDER_HISTORY_REFRESH_CHECK
LIMIT 20;
-- INTERPRET: compare originals with converted dates; inspect NULLs/wrong years.
-- A successful sample is useful, but we must also check every row below.

-- ============================================================================
-- 6. VALIDATE DATES ACROSS THE WHOLE FILE
-- ============================================================================
-- WHY: twenty good examples do not prove every row can be converted.
-- WITH defines a CTE: a named query result, not a permanent table.
-- Regex checks the number of digits before parsing. This also prevents LPAD
-- from silently shortening an unexpectedly long shipped-date value.
WITH parsed_dates AS (
    SELECT *,
        CASE WHEN REGEXP_LIKE(order_date, '[0-9]{8}')
            THEN TRY_TO_DATE(order_date, 'YYYYMMDD') END AS parsed_order,
        CASE WHEN REGEXP_LIKE(scheduled_ship_date, '[0-9]{8}')
            THEN TRY_TO_DATE(scheduled_ship_date, 'YYYYMMDD') END AS parsed_scheduled,
        CASE WHEN REGEXP_LIKE(shipped_date, '[0-9]{5,6}')
            THEN TRY_TO_DATE(LPAD(shipped_date, 6, '0'), 'MMDDYY') END AS parsed_shipped
    FROM RAW.ORDER_HISTORY_REFRESH_CHECK
)
SELECT
    COUNT(*) AS total_rows,
    COALESCE(COUNT_IF(order_date IS NULL), 0) AS missing_order_dates,
    COALESCE(COUNT_IF(scheduled_ship_date IS NULL), 0) AS missing_scheduled_dates,
    COALESCE(COUNT_IF(shipped_date IS NULL), 0) AS missing_shipped_dates,
    COALESCE(COUNT_IF(order_date IS NOT NULL AND parsed_order IS NULL), 0) AS invalid_order_dates,
    COALESCE(COUNT_IF(scheduled_ship_date IS NOT NULL AND parsed_scheduled IS NULL), 0) AS invalid_scheduled_dates,
    COALESCE(COUNT_IF(shipped_date IS NOT NULL AND parsed_shipped IS NULL), 0) AS invalid_shipped_dates,
    MIN(parsed_shipped) AS earliest_shipped_date,
    MAX(parsed_shipped) AS latest_shipped_date
FROM parsed_dates;
-- COUNT_IF counts rows satisfying a condition. COALESCE turns a NULL count into 0.
-- Missing = no source value; invalid = a source value exists but cannot be parsed.
-- INTERPRET: this file had 554580 rows, all six problem counts zero, and shipped
-- dates from 2025-06-06 to 2026-07-09. Investigate differences before proceeding.
-- A valid calendar date still needs business context to know it is correct.

-- ============================================================================
-- 7. CHECK FILE LINEAGE AND PRIVACY FLAGS
-- ============================================================================
-- WHY: confirm which ingestion data was reprocessed and which file was loaded.
-- Group by BOTH source batch and filename so multiple files cannot be hidden.
SELECT
    batch_id,
    source_filename,
    COUNT(*) AS row_count,
    MIN(pseudonymized_at) AS earliest_privacy_processing,
    MAX(pseudonymized_at) AS latest_privacy_processing,
    MAX(ingested_at) AS snowflake_load_time
FROM RAW.ORDER_HISTORY_REFRESH_CHECK
GROUP BY batch_id, source_filename;
-- INTERPRET for this example: July ingestion ID, September privacy timestamp,
-- and the September S3 filename. These values describe different events.
-- The earlier check comparing row BATCH_ID to the September filename ID was
-- incorrect and has been removed. It falsely flagged all 554580 rows.

SELECT
    COUNT(*) AS total_rows,
    -- This comparison uses the verified SOURCE ingestion ID, not the file ID.
    COALESCE(COUNT_IF(batch_id IS NULL OR batch_id <> '20260715_181006'), 0)
        AS unexpected_source_batch,
    COALESCE(COUNT_IF(
        source_filename IS NULL OR source_file_row_number IS NULL
        OR source_file_last_modified IS NULL OR ingested_at IS NULL
    ), 0) AS rows_missing_metadata,
    COALESCE(COUNT_IF(original_company_code_removed IS DISTINCT FROM TRUE), 0)
        AS company_code_not_confirmed,
    COALESCE(COUNT_IF(original_purchase_order_number_removed IS DISTINCT FROM TRUE), 0)
        AS purchase_order_not_confirmed,
    COALESCE(COUNT_IF(original_customer_name_removed IS DISTINCT FROM TRUE), 0)
        AS customer_name_not_confirmed,
    COALESCE(COUNT_IF(original_sku_codes_removed IS DISTINCT FROM TRUE), 0)
        AS sku_codes_not_confirmed,
    COALESCE(COUNT_IF(original_product_description_removed IS DISTINCT FROM TRUE), 0)
        AS product_description_not_confirmed,
    COALESCE(COUNT_IF(original_product_category_removed IS DISTINCT FROM TRUE), 0)
        AS product_category_not_confirmed
FROM RAW.ORDER_HISTORY_REFRESH_CHECK;
-- IS DISTINCT FROM TRUE catches FALSE and NULL (not explicitly confirmed).
-- INTERPRET: expect 554580 rows and zero in each problem column for this file.
-- Flags report what Python says it did; they do not independently prove the
-- actual values were properly pseudonymized. Keep the upstream quality checks.

-- ============================================================================
-- 8. BUILD THE READY TABLE WITH REAL DATE COLUMNS
-- ============================================================================
-- WHY: RAW expects DATE values, so apply the rules already checked above.
-- TO_DATE now stops on conversion errors instead of quietly returning NULL.
-- BATCH_ID, privacy flags, and file metadata are carried through unchanged.
CREATE TEMPORARY TABLE RAW.ORDER_HISTORY_REFRESH_READY AS
SELECT * REPLACE (
    TO_DATE(order_date, 'YYYYMMDD') AS order_date,
    TO_DATE(scheduled_ship_date, 'YYYYMMDD') AS scheduled_ship_date,
    TO_DATE(LPAD(shipped_date, 6, '0'), 'MMDDYY') AS shipped_date
)
FROM RAW.ORDER_HISTORY_REFRESH_CHECK;

SELECT
    COUNT(*) AS total_rows,
    MIN(shipped_date) AS earliest_shipped_date,
    MAX(shipped_date) AS latest_shipped_date,
    COUNT(DISTINCT batch_id) AS source_batch_count
FROM RAW.ORDER_HISTORY_REFRESH_READY;
-- INTERPRET: expect 554580, 2025-06-06, 2026-07-09, and 1 respectively.
-- The real RAW table is still unchanged. This is the final checkpoint before
-- choosing to publish. Stop if the preceding checks did not match expectations.

-- ============================================================================
-- 9. PUBLISH, INSPECT, THEN CHOOSE COMMIT OR ROLLBACK (MANUAL STEP)
-- ============================================================================
-- WHY: a transaction keeps removal and insertion together as one change.
-- Remove only this source-file observation; older weekly files must survive.
-- All temporary-table creation must happen BEFORE BEGIN: CREATE/ALTER commands
-- can commit active transactions. Do not run them during this step.
--
-- This block is a saved example, not automatically executed. When deliberately
-- refreshing, run BEGIN through the inspection SELECT below. If ANY statement
-- fails, execute ROLLBACK. Otherwise inspect the results, then choose exactly
-- one finishing command. Finish in the same session without leaving it open.
/*
BEGIN TRANSACTION;

DELETE FROM RAW.ORDER_HISTORY
WHERE source_filename = (
    SELECT MIN(source_filename) FROM RAW.ORDER_HISTORY_REFRESH_READY
);

-- Column order matches because READY was derived from RAW using SELECT * REPLACE.
-- Recheck this assumption if either table's column structure changes later.
INSERT INTO RAW.ORDER_HISTORY
SELECT * FROM RAW.ORDER_HISTORY_REFRESH_READY;

SELECT
    batch_id, source_filename, COUNT(*) AS row_count,
    MIN(shipped_date) AS earliest_shipped_date,
    MAX(shipped_date) AS latest_shipped_date,
    MAX(pseudonymized_at) AS privacy_processing_time
FROM RAW.ORDER_HISTORY
GROUP BY batch_id, source_filename;

-- If everything succeeded and the result matches, execute:
-- COMMIT;

-- If any statement failed or the result is unexpected, execute instead:
-- ROLLBACK;
*/
-- COMMIT saves this file-partition replacement; ROLLBACK undoes it.
-- Merely reaching the last line of a worksheet does not approve the result.

-- ============================================================================
-- 10. CONFIRM WHAT WAS SAVED (READ-ONLY)
-- ============================================================================
-- WHY: distinguish checking pending changes from verifying committed data.
-- Run AFTER COMMIT or ROLLBACK. The same query is useful here because it answers
-- a different question: what is now saved in the real table?
SELECT
    batch_id, source_filename, COUNT(*) AS row_count,
    MIN(shipped_date) AS earliest_shipped_date,
    MAX(shipped_date) AS latest_shipped_date,
    MAX(pseudonymized_at) AS privacy_processing_time
FROM RAW.ORDER_HISTORY
GROUP BY batch_id, source_filename;
-- After COMMIT, expect the July source batch with the September filename and
-- privacy timestamp, 554580 rows, and the verified shipped-date range.
-- After ROLLBACK, expect the previously committed contents instead.
--
-- End of refresh. General SHOW TABLES / SHOW VIEWS commands were omitted because
-- they explore the schema but do not verify this specific data replacement.
