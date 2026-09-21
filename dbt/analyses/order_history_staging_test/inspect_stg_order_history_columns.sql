-- Read Snowflake's catalogue of columns.
-- This describes the built view; it does not change it.

select
    ordinal_position as column_position,
    column_name,
    data_type,

    -- Relevant to numeric columns.
    numeric_precision,
    numeric_scale,

    -- Describes the column's declared nullability.
    -- This does not count actual missing values.
    is_nullable

from {{ target.database }}.information_schema.columns

where table_schema = upper('{{ target.schema }}')
  and table_name = 'STG_ORDER_HISTORY'

order by ordinal_position