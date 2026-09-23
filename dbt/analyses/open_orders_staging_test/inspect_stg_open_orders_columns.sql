/*
Purpose:
    Inspect the actual columns and types Snowflake created for
    STG_OPEN_ORDERS.

This reads Snowflake metadata. It does not change the view.
*/

select
    ordinal_position as column_position,
    column_name,
    data_type,
    numeric_precision,
    numeric_scale,
    is_nullable

from {{ target.database }}.information_schema.columns

where table_schema = upper('{{ target.schema }}')
  and table_name = 'STG_OPEN_ORDERS'

order by ordinal_position