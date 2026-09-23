/*
Purpose:
    Confirm that the four numeric date fields can be converted
    from YYYYMMDD into real Snowflake DATE values.

Why use TRY_TO_DATE?
    TRY_TO_DATE returns NULL for an invalid value instead of stopping
    the entire query with an error. That lets us count invalid values.

Missing and invalid are counted separately:
    - Missing: the source supplied NULL.
    - Invalid: the source supplied a value that cannot become a date.
*/

with source_dates as (

    select
        order_date as raw_order_date,
        scheduled_ship_date as raw_scheduled_ship_date,
        customer_requested_date as raw_customer_requested_date,
        revised_delivery_date as raw_revised_delivery_date

    from {{ source('order_intelligence_raw', 'open_orders') }}

),

converted_dates as (

    select
        *,

        try_to_date(
            raw_order_date::varchar,
            'YYYYMMDD'
        ) as converted_order_date,

        try_to_date(
            raw_scheduled_ship_date::varchar,
            'YYYYMMDD'
        ) as converted_scheduled_ship_date,

        try_to_date(
            raw_customer_requested_date::varchar,
            'YYYYMMDD'
        ) as converted_customer_requested_date,

        try_to_date(
            raw_revised_delivery_date::varchar,
            'YYYYMMDD'
        ) as converted_revised_delivery_date

    from source_dates

)

select
    count(*) as total_rows,

    -- Missing-value checks.
    count_if(raw_order_date is null)
        as missing_order_dates,

    count_if(raw_scheduled_ship_date is null)
        as missing_scheduled_ship_dates,

    count_if(raw_customer_requested_date is null)
        as missing_customer_requested_dates,

    count_if(raw_revised_delivery_date is null)
        as missing_revised_delivery_dates,

    -- Invalid means the source supplied something,
    -- but our YYYYMMDD conversion could not interpret it.
    count_if(
        raw_order_date is not null
        and converted_order_date is null
    ) as invalid_order_dates,

    count_if(
        raw_scheduled_ship_date is not null
        and converted_scheduled_ship_date is null
    ) as invalid_scheduled_ship_dates,

    count_if(
        raw_customer_requested_date is not null
        and converted_customer_requested_date is null
    ) as invalid_customer_requested_dates,

    count_if(
        raw_revised_delivery_date is not null
        and converted_revised_delivery_date is null
    ) as invalid_revised_delivery_dates,

    -- Date ranges help us spot conversions that technically worked
    -- but produced dates outside a reasonable business period.
    min(converted_order_date) as earliest_order_date,
    max(converted_order_date) as latest_order_date,

    min(converted_scheduled_ship_date)
        as earliest_scheduled_ship_date,
    max(converted_scheduled_ship_date)
        as latest_scheduled_ship_date,

    min(converted_customer_requested_date)
        as earliest_customer_requested_date,
    max(converted_customer_requested_date)
        as latest_customer_requested_date,

    min(converted_revised_delivery_date)
        as earliest_revised_delivery_date,
    max(converted_revised_delivery_date)
        as latest_revised_delivery_date

from converted_dates