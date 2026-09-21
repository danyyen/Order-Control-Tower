-- =========================================================
-- OPEN_ORDERS - TABLE SETUP AND READ-ONLY DATA CHECKS
-- =========================================================
-- Each file is a complete current-state observation, but RAW retains every
-- weekly observation for backlog history. Downstream dbt models select the
-- latest file when they need the current open-order state. Reloading the same
-- source filename replaces only that file's rows.
--
-- Run 01_project_setup.sql first. Run this file to create a missing table,
-- add missing load-metadata columns, and inspect the data already loaded.
-- This file does not remove rows or load files.
-- Weekly loads: python src/warehouse/load_open_orders_to_snowflake.py
-- See snowflake/README.md for connection settings and the run order.

USE ROLE ORDER_INTELLIGENCE_LOADER;
USE DATABASE ORDER_INTELLIGENCE_DB;
USE SCHEMA RAW;
USE WAREHOUSE ORDER_INTELLIGENCE_WH;

-- =========================================================
-- 1. DISCOVER FILES
-- =========================================================
-- @ means a stage: a saved pointer to files in S3. LIST does not load data.
LIST @ORDER_INTELLIGENCE_S3_STAGE/open_orders/;

-- =========================================================
-- 2. CREATE THE TABLE ONLY IF IT DOES NOT EXIST
-- =========================================================
-- INFER_SCHEMA guesses column names and types from staged CSV files.
-- USING TEMPLATE uses those results as the definition of a NEW table.
-- ARRAY_AGG collects column definitions; OBJECT_CONSTRUCT describes each one.
-- WITHIN GROUP keeps columns in the order reported by INFER_SCHEMA.
-- PARSE_HEADER in the named file format reads names from the CSV header.
-- IGNORE_CASE makes the inferred column names uppercase for unquoted SQL.
--
-- Bootstrap requires approved CSV files at this dataset's stage path.
-- Before the FIRST run, inspect inferred types below, especially numeric-
-- looking identifiers (leading zeros), dates, and decimal quantities.
-- Inference is discovery, not proof that future files have the same schema.
--
-- SELECT * FROM TABLE(INFER_SCHEMA(
--     LOCATION => '@ORDER_INTELLIGENCE_S3_STAGE/open_orders/',
--     FILE_FORMAT => 'ORDER_INTELLIGENCE_CSV_HEADER_FF',
--     IGNORE_CASE => TRUE
-- )) ORDER BY ORDER_ID;
--
-- IF NOT EXISTS preserves the existing table, rows, types, and grants.
-- It does NOT update types if files change. Review DESCRIBE TABLE and use
-- an intentional ALTER TABLE migration when the source schema changes.
-- In particular, never switch this to CREATE OR REPLACE for routine setup.
CREATE TABLE IF NOT EXISTS RAW.OPEN_ORDERS
USING TEMPLATE (
    SELECT ARRAY_AGG(
        OBJECT_CONSTRUCT(
            'COLUMN_NAME', COLUMN_NAME,
            'TYPE', TYPE,
            'NULLABLE', NULLABLE
        )
    )
    WITHIN GROUP (ORDER BY ORDER_ID)
    FROM TABLE(
        INFER_SCHEMA(
            LOCATION => '@ORDER_INTELLIGENCE_S3_STAGE/open_orders/',
            FILE_FORMAT => 'ORDER_INTELLIGENCE_CSV_HEADER_FF',
            IGNORE_CASE => TRUE
        )
    )
);

-- =========================================================
-- 3. ADD LOAD METADATA IF MISSING
-- =========================================================
-- Metadata describes where a row came from. COPY fills these fields.
-- Each IF NOT EXISTS makes this step safe to rerun, including after a
-- partially completed setup. Existing column types are left unchanged.
ALTER TABLE RAW.OPEN_ORDERS ADD COLUMN IF NOT EXISTS SOURCE_FILENAME VARCHAR;
ALTER TABLE RAW.OPEN_ORDERS ADD COLUMN IF NOT EXISTS SOURCE_FILE_ROW_NUMBER NUMBER;
ALTER TABLE RAW.OPEN_ORDERS ADD COLUMN IF NOT EXISTS SOURCE_FILE_LAST_MODIFIED TIMESTAMP_NTZ;
ALTER TABLE RAW.OPEN_ORDERS ADD COLUMN IF NOT EXISTS INGESTED_AT TIMESTAMP_LTZ;
-- VARCHAR = text; NUMBER = whole number here.
-- NTZ = timestamp without a time zone; LTZ displays in the session time zone.
-- INGESTED_AT records when Snowflake scanned the file, not its business date.

-- =========================================================
-- 4. REVIEW THE STRUCTURE AND LOADED FILES
-- =========================================================
DESCRIBE TABLE RAW.OPEN_ORDERS;
-- If the table is new, these queries return zero rows/counts until Python loads it.
SELECT COUNT(*) AS total_rows FROM RAW.OPEN_ORDERS;
SELECT batch_id, source_filename, COUNT(*) AS row_count
FROM RAW.OPEN_ORDERS
GROUP BY batch_id, source_filename;

-- =========================================================
-- 5. TEST A POSSIBLE BUSINESS KEY
-- =========================================================
-- A business key identifies one logical record. This combination is only
-- a candidate until the source's business rules and actual data support it.
-- Repeated keys are not necessarily identical rows. Never delete them merely
-- to make a uniqueness test pass.
-- DISTINCT counts actual combinations, avoiding concatenated-string collisions.
-- NULL-containing combinations count here; missing fields are checked below.
SELECT
    (SELECT COUNT(*) FROM RAW.OPEN_ORDERS) AS total_rows,
    (SELECT COUNT(*) FROM (
        SELECT DISTINCT company_code, order_number, unique_sku_code FROM RAW.OPEN_ORDERS
    ) AS candidate_keys) AS distinct_candidate_keys;

-- GROUP BY collects matching keys; HAVING keeps groups with multiple rows.
SELECT company_code, order_number, unique_sku_code, COUNT(*) AS row_count
FROM RAW.OPEN_ORDERS
GROUP BY company_code, order_number, unique_sku_code
HAVING COUNT(*) > 1
ORDER BY row_count DESC;

-- Show individual rows in repeated groups, including groups with NULL keys.
-- PARTITION BY counts each group without collapsing its rows.
-- QUALIFY filters using that calculated count. LIMIT bounds terminal output.
SELECT * FROM RAW.OPEN_ORDERS
QUALIFY COUNT(*) OVER (PARTITION BY company_code, order_number, unique_sku_code) > 1
ORDER BY company_code, order_number, unique_sku_code
LIMIT 100;

-- Missing key fields need investigation even if populated keys are unique.
SELECT
    COALESCE(COUNT_IF(company_code IS NULL), 0) AS null_company_code,
    COALESCE(COUNT_IF(order_number IS NULL), 0) AS null_order_number,
    COALESCE(COUNT_IF(unique_sku_code IS NULL), 0) AS null_unique_sku_code
FROM RAW.OPEN_ORDERS;

-- row_hash fingerprints selected source values; it is not a permanent row ID.
-- Equal hashes suggest rows to investigate, not proof all columns are equal.
SELECT row_hash, COUNT(*) AS row_count
FROM RAW.OPEN_ORDERS
GROUP BY row_hash
HAVING COUNT(*) > 1
ORDER BY row_count DESC
LIMIT 100;
