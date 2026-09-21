-- Read-only terminal connection test. Creates or changes no objects.
-- Run from the project root:
-- python src/warehouse/run_sql_file.py snowflake/check_connection.sql
SELECT
    CURRENT_USER() AS connected_user,
    CURRENT_ROLE() AS active_role,
    CURRENT_ACCOUNT() AS account_identifier,
    CURRENT_DATABASE() AS active_database,
    CURRENT_SCHEMA() AS active_schema,
    CURRENT_WAREHOUSE() AS active_warehouse;
