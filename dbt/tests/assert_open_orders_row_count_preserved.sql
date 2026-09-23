-- Return one failing record only when source and staging counts differ.

with raw_count as (

    select count(*) as row_count
    from {{ source('order_intelligence_raw', 'open_orders') }}

),

staging_count as (

    select count(*) as row_count
    from {{ ref('stg_open_orders') }}

)

select
    raw_count.row_count as raw_rows,
    staging_count.row_count as staging_rows

from raw_count
cross join staging_count

where raw_count.row_count <> staging_count.row_count