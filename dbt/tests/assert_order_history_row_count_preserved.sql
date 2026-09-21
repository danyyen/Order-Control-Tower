-- Compare the current source and staging counts.
-- Return one failing row only when their counts differ.

with raw_count as (
    select count(*) as row_count
    from {{ source('order_intelligence_raw', 'order_history') }}
),

staging_count as (
    select count(*) as row_count
    from {{ ref('stg_order_history') }}
)

select
    raw_count.row_count as raw_rows,
    staging_count.row_count as staging_rows

-- Each CTE contains exactly one row, so this produces one comparison.
from raw_count
cross join staging_count

where raw_count.row_count <> staging_count.row_count