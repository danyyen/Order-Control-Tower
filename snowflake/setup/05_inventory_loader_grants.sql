-- Run after 03_inventory_raw_table.sql, as an administrator with grant rights.
-- This explicit grant lets ingestion work even if another role owns INVENTORY.
-- It changes permissions only; it does not delete any rows.
USE ROLE SECURITYADMIN;
GRANT DELETE ON TABLE ORDER_INTELLIGENCE_DB.RAW.INVENTORY
    TO ROLE ORDER_INTELLIGENCE_LOADER;
USE ROLE ORDER_INTELLIGENCE_LOADER;
