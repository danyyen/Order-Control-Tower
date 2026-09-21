-- Compare the source with the staging model.
-- Both counts should match because staging preserves every record.

select
    'raw' as layer,
    count(*) as row_count
from {{ source('order_intelligence_raw', 'order_history') }}

union all

select
    'staging' as layer,
    count(*) as row_count
from {{ ref('stg_order_history') }}