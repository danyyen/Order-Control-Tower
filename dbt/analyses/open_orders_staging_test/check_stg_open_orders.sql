/*
Purpose:
    Compare RAW.OPEN_ORDERS with STG_OPEN_ORDERS after building
    the staging view.

Checks:
    1. Staging preserves all source records.
    2. Source date placeholder 0 becomes NULL.
    3. Valid non-zero source dates convert successfully.

This is an investigation query, not yet an automated test.
*/

with raw_summary as (

    select
        count(*) as raw_rows,

        -- Count the source placeholder values.
        count_if(order_date = 0)
            as raw_zero_order_dates,

        count_if(scheduled_ship_date = 0)
            as raw_zero_scheduled_ship_dates,

        count_if(customer_requested_date = 0)
            as raw_zero_customer_requested_dates,

        count_if(revised_delivery_date = 0)
            as raw_zero_revised_delivery_dates,

        -- Find non-zero values that still cannot become dates.
        -- These would represent unexpected source values.
        count_if(
            order_date is not null
            and order_date <> 0
            and try_to_date(order_date::varchar, 'YYYYMMDD') is null
        ) as unexpected_invalid_order_dates,

        count_if(
            scheduled_ship_date is not null
            and scheduled_ship_date <> 0
            and try_to_date(
                scheduled_ship_date::varchar,
                'YYYYMMDD'
            ) is null
        ) as unexpected_invalid_scheduled_dates,

        count_if(
            customer_requested_date is not null
            and customer_requested_date <> 0
            and try_to_date(
                customer_requested_date::varchar,
                'YYYYMMDD'
            ) is null
        ) as unexpected_invalid_customer_requested_dates,

        count_if(
            revised_delivery_date is not null
            and revised_delivery_date <> 0
            and try_to_date(
                revised_delivery_date::varchar,
                'YYYYMMDD'
            ) is null
        ) as unexpected_invalid_revised_delivery_dates

    from {{ source('order_intelligence_raw', 'open_orders') }}

),

staging_summary as (

    select
        count(*) as staging_rows,

        -- The six source zero values should now be NULL.
        count_if(order_date is null)
            as staging_null_order_dates,

        count_if(scheduled_ship_date is null)
            as staging_null_scheduled_ship_dates,

        count_if(customer_requested_date is null)
            as staging_null_customer_requested_dates,

        count_if(revised_delivery_date is null)
            as staging_null_revised_delivery_dates

    from {{ ref('stg_open_orders') }}

)

select
    raw_summary.*,
    staging_summary.*

from raw_summary
cross join staging_summary