-- Check how many rows dbt can read from each RAW table.
-- This query reads data; it does not change any tables.
-- source(...) finds the Snowflake table using your YAML definition.

select
    'order_history' as source_table,
    count(*) as row_count
from {{ source('order_intelligence_raw', 'order_history') }}

union all

select
    'open_orders' as source_table,
    count(*) as row_count
from {{ source('order_intelligence_raw', 'open_orders') }}

union all

select
    'inventory' as source_table,
    count(*) as row_count
from {{ source('order_intelligence_raw', 'inventory') }}