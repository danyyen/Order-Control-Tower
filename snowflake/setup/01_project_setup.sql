-- =========================================================
-- ORDER INTELLIGENCE - SNOWFLAKE PROJECT SETUP
-- =========================================================
-- PURPOSE: prepare Snowflake to read this project's CSV files from S3.
-- This script creates the containers, compute, connection, and permissions.
-- It does not create the order table or load rows into it.
--
-- HOW THE PIECES FIT:
-- S3 bucket -> stage (file location) -> COPY INTO -> RAW table
-- A storage integration supplies permission to connect to AWS.
-- A file format tells Snowflake how to interpret the CSV text.
-- A warehouse supplies the computing power used to load/query data.
-- A role is a named collection of permissions assigned to a user.
--
-- BEFORE RUNNING:
-- 1. Confirm the AWS account, bucket, IAM role, and user DANYYEN below.
-- 2. Use a Snowflake administrator who can switch to ACCOUNTADMIN and
--    SECURITYADMIN. SECURITYADMIN alone cannot create all these objects
--    with its default permissions.
-- 3. Run sections in order. On first setup, complete the AWS work in
--    section 6 before continuing to the S3 access test.
--
-- This small-project bootstrap uses ACCOUNTADMIN to create objects.
-- Daily ingestion uses ORDER_INTELLIGENCE_LOADER instead.
-- A dbt transformer role and its output schemas are NOT created here;
-- set those up separately before running dbt.
--
-- RERUNS: IF NOT EXISTS keeps existing objects and their data/settings.
-- It does NOT update an existing object to match the settings below.
-- Use a deliberate ALTER statement when an existing setting must change.

USE ROLE ACCOUNTADMIN;

-- =========================================================
-- 1. CREATE THE PROJECT DATABASE
-- =========================================================
-- A database is the top-level container for this project's data objects.
CREATE DATABASE IF NOT EXISTS ORDER_INTELLIGENCE_DB;

-- =========================================================
-- 2. CREATE THE RAW SCHEMA
-- =========================================================
-- A schema is a folder-like container inside a database.
-- RAW will hold source data before business transformations are applied.
CREATE SCHEMA IF NOT EXISTS ORDER_INTELLIGENCE_DB.RAW;

-- =========================================================
-- 3. CREATE THE COMPUTE WAREHOUSE
-- =========================================================
-- A warehouse runs work; the database stores data independently of it.
CREATE WAREHOUSE IF NOT EXISTS ORDER_INTELLIGENCE_WH
WITH
WAREHOUSE_SIZE = 'XSMALL'       -- Small starting size for project workloads.
AUTO_SUSPEND = 60              -- Suspend compute after 60 seconds of inactivity.
AUTO_RESUME = TRUE             -- Start compute again when work needs it.
INITIALLY_SUSPENDED = TRUE;    -- Create it without immediately starting compute.
-- Suspension reduces idle compute costs; stored data still has storage costs.

-- =========================================================
-- 4. SET THE CURRENT WORKING LOCATION
-- =========================================================
-- USE changes this session's defaults. It does not move any data.
-- For example, a short stage name below refers to an object in DB.RAW.
USE DATABASE ORDER_INTELLIGENCE_DB;
USE SCHEMA RAW;
USE WAREHOUSE ORDER_INTELLIGENCE_WH;

-- =========================================================
-- 5. CREATE THE CONNECTION TO AWS
-- =========================================================
-- A storage integration lets Snowflake assume an AWS IAM role without
-- putting AWS access keys into this SQL script.
-- ARN means Amazon Resource Name: an identifier for an AWS resource.
-- The AWS role and bucket must already exist; this SQL does not create them.
--
-- Keep IF NOT EXISTS here. Replacing an integration can generate a new
-- external ID and break AWS trust. It also breaks existing stage links
-- because stages refer to the integration's hidden internal ID.
-- The IAM user ARN is shared by S3 integrations in a Snowflake account;
-- recreating an integration does not necessarily change that ARN.
CREATE STORAGE INTEGRATION IF NOT EXISTS ORDER_INTELLIGENCE_S3_INT
TYPE = EXTERNAL_STAGE
STORAGE_PROVIDER = 'S3'
STORAGE_AWS_ROLE_ARN =
    'arn:aws:iam::248542435654:role/SnowflakeOrderIntelligenceRole'
ENABLED = TRUE
STORAGE_ALLOWED_LOCATIONS = (
    's3://order-intelligence-248542435654-us-east-1-an/order-intelligence/landing/'
);
-- ALLOWED_LOCATIONS limits which S3 paths this integration can use.
-- AWS must ALSO grant access; this setting alone gives no AWS permissions.

-- =========================================================
-- 6. READ THE CONNECTION DETAILS AND CONFIGURE AWS TRUST
-- =========================================================
-- DESC means DESCRIBE: display the integration's settings.
DESC INTEGRATION ORDER_INTELLIGENCE_S3_INT;

-- FIRST-TIME MANUAL STEP: pause here and configure the AWS IAM role.
-- In its trust policy, use these two values from the result above:
--   STORAGE_AWS_IAM_USER_ARN -> Principal.AWS
--   STORAGE_AWS_EXTERNAL_ID  -> Condition.StringEquals['sts:ExternalId']
-- The trust policy must allow the sts:AssumeRole action.
-- This tells AWS which Snowflake identity can assume the role and under
-- which external ID (a value used to distinguish the intended connection).
--
-- The role also needs an S3 permissions policy allowing bucket listing
-- and object reads for the landing path. Trust and S3 permissions are
-- separate: trust permits assuming the role; permissions permit reading.
-- For SSE-KMS encrypted files, configure the required KMS decrypt access too.
-- Follow the complete AWS policy examples in the Snowflake guide:
-- https://docs.snowflake.com/en/user-guide/data-load-s3-config-storage-integration

-- =========================================================
-- 7. OPTIONAL: UPDATE THE ALLOWED PATH LATER
-- =========================================================
-- No update is needed for a new integration created with the path above.
-- This commented example changes settings while preserving the integration.
-- If you change buckets/paths, also update AWS permissions AND the stage URL.
-- Editing CREATE ... IF NOT EXISTS does not update an existing stage.
--
-- ALTER STORAGE INTEGRATION ORDER_INTELLIGENCE_S3_INT
-- SET STORAGE_ALLOWED_LOCATIONS = (
--     's3://order-intelligence-248542435654-us-east-1-an/order-intelligence/landing/'
-- );
-- ALTER STAGE ORDER_INTELLIGENCE_DB.RAW.ORDER_INTELLIGENCE_S3_STAGE
-- SET URL = 's3://order-intelligence-248542435654-us-east-1-an/order-intelligence/landing/';

-- =========================================================
-- 8. DEFINE HOW TO READ CSV FILES
-- =========================================================
-- A file format is a saved set of parsing rules; it stores no CSV data.
-- We use two because skipping a header and reading column names serve
-- different purposes. SKIP_HEADER and PARSE_HEADER cannot be used together.

-- Format A: skip the header for positional reads such as SELECT $1, $2.
-- $1 means the first CSV field, $2 means the second, and so on.
CREATE FILE FORMAT IF NOT EXISTS ORDER_INTELLIGENCE_CSV_FF
TYPE = CSV
FIELD_DELIMITER = ','                   -- Commas separate fields.
SKIP_HEADER = 1                         -- Ignore the first line in each file.
FIELD_OPTIONALLY_ENCLOSED_BY = '"'       -- Read "Toronto, ON" as one field.
TRIM_SPACE = TRUE                       -- Remove surrounding field spaces.
NULL_IF = ('NULL', 'null', '')          -- Treat these values as missing data.
EMPTY_FIELD_AS_NULL = TRUE;             -- An empty unquoted field is NULL too.
-- NULL means missing/unknown, not the number zero.
-- These rules also turn a literal string 'NULL' into missing data.

-- Format B: use the header as column names for schema discovery with
-- INFER_SCHEMA and CSV loading with COPY INTO ... MATCH_BY_COLUMN_NAME.
-- The loading command must explicitly select this format because the
-- stage below uses Format A by default.
CREATE FILE FORMAT IF NOT EXISTS ORDER_INTELLIGENCE_CSV_HEADER_FF
TYPE = CSV
FIELD_DELIMITER = ','
PARSE_HEADER = TRUE                     -- First row supplies column names.
FIELD_OPTIONALLY_ENCLOSED_BY = '"'
TRIM_SPACE = TRUE
NULL_IF = ('NULL', 'null', '')
EMPTY_FIELD_AS_NULL = TRUE;
-- IF NOT EXISTS preserves existing formats and their grants on reruns.
-- Use ALTER FILE FORMAT to deliberately change an existing parsing rule.

-- =========================================================
-- 9. CREATE THE EXTERNAL STAGE
-- =========================================================
-- A stage is a named pointer to files. Creating it does not copy files
-- into Snowflake or create a table. The @ symbol refers to a stage in SQL.
CREATE STAGE IF NOT EXISTS ORDER_INTELLIGENCE_S3_STAGE
URL = 's3://order-intelligence-248542435654-us-east-1-an/order-intelligence/landing/'
STORAGE_INTEGRATION = ORDER_INTELLIGENCE_S3_INT
FILE_FORMAT = (FORMAT_NAME = 'ORDER_INTELLIGENCE_CSV_FF');

-- =========================================================
-- 10. TEST WHETHER SNOWFLAKE CAN LIST THE S3 FILES
-- =========================================================
LIST @ORDER_INTELLIGENCE_S3_STAGE;
-- Expect file names if the path contains files; an empty path returns no rows.
-- An access error means the connection/permissions need investigation.
-- LIST checks listing access, not whether CSV contents will load correctly.

-- =========================================================
-- 11. GIVE THE LOADER ROLE ITS PERMISSIONS
-- =========================================================
-- RBAC means role-based access control: grant permissions to a role,
-- then give a person or service that role.
-- SECURITYADMIN manages roles and grants. The loader handles daily loads.
USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS ORDER_INTELLIGENCE_LOADER;

-- USAGE permits access to a container or resource. It does not by itself
-- permit reading or changing the tables inside that container.
GRANT USAGE ON WAREHOUSE ORDER_INTELLIGENCE_WH
    TO ROLE ORDER_INTELLIGENCE_LOADER;
GRANT USAGE ON DATABASE ORDER_INTELLIGENCE_DB
    TO ROLE ORDER_INTELLIGENCE_LOADER;
GRANT USAGE ON SCHEMA ORDER_INTELLIGENCE_DB.RAW
    TO ROLE ORDER_INTELLIGENCE_LOADER;

-- Allow the loader to create the RAW tables in the next setup script.
-- A role owns tables it creates, so it has broader control over those
-- tables than just the SELECT/INSERT/DELETE grants listed below.
GRANT CREATE TABLE ON SCHEMA ORDER_INTELLIGENCE_DB.RAW
    TO ROLE ORDER_INTELLIGENCE_LOADER;

-- SELECT reads rows. INSERT adds rows (including through COPY INTO).
-- DELETE removes only the observation partition being corrected/retried.
-- FUTURE TABLES applies to tables created later; ALL TABLES covers tables
-- that already exist. Both are needed to cover both groups.
GRANT SELECT, INSERT, DELETE ON FUTURE TABLES IN SCHEMA ORDER_INTELLIGENCE_DB.RAW
    TO ROLE ORDER_INTELLIGENCE_LOADER;
GRANT SELECT, INSERT, DELETE ON ALL TABLES IN SCHEMA ORDER_INTELLIGENCE_DB.RAW
    TO ROLE ORDER_INTELLIGENCE_LOADER;

-- Allow access to the integration, stage, and both CSV parsing formats.
GRANT USAGE ON INTEGRATION ORDER_INTELLIGENCE_S3_INT
    TO ROLE ORDER_INTELLIGENCE_LOADER;
GRANT USAGE ON STAGE ORDER_INTELLIGENCE_DB.RAW.ORDER_INTELLIGENCE_S3_STAGE
    TO ROLE ORDER_INTELLIGENCE_LOADER;
GRANT USAGE ON FILE FORMAT ORDER_INTELLIGENCE_DB.RAW.ORDER_INTELLIGENCE_CSV_FF
    TO ROLE ORDER_INTELLIGENCE_LOADER;
GRANT USAGE ON FILE FORMAT ORDER_INTELLIGENCE_DB.RAW.ORDER_INTELLIGENCE_CSV_HEADER_FF
    TO ROLE ORDER_INTELLIGENCE_LOADER;

-- DANYYEN must be an existing Snowflake user. Change this if necessary.
GRANT ROLE ORDER_INTELLIGENCE_LOADER TO USER DANYYEN;

-- Review directly assigned permissions and grants for future tables.
-- Rerunning GRANT adds permissions; it does not remove older extra grants.
SHOW GRANTS TO ROLE ORDER_INTELLIGENCE_LOADER;
SHOW FUTURE GRANTS TO ROLE ORDER_INTELLIGENCE_LOADER;

-- =========================================================
-- 12. SWITCH TO THE ROLE USED FOR DAILY INGESTION
-- =========================================================
-- The current user must have this role to select it.
-- If a different administrator ran setup, continue here in DANYYEN's session
-- (or a session belonging to another user granted this role).
USE ROLE ORDER_INTELLIGENCE_LOADER;
USE DATABASE ORDER_INTELLIGENCE_DB;
USE SCHEMA RAW;
USE WAREHOUSE ORDER_INTELLIGENCE_WH;

-- Display the session settings so you can check where commands will run.
SELECT CURRENT_ROLE(), CURRENT_DATABASE(), CURRENT_SCHEMA(), CURRENT_WAREHOUSE();

-- Test listing again using the loader's permissions, not the admin's.
LIST @ORDER_INTELLIGENCE_S3_STAGE;
-- Next: review 02_order_history_raw_table.sql before running it.
-- Its optional manual load is commented out; daily loads use Python.

-- After creating INVENTORY with file 03, run 05_inventory_loader_grants.sql
-- to grant DELETE explicitly if the loader does not own that table.
