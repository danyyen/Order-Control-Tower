/*
Purpose:
    Show the records containing date values that cannot be converted
    using the expected YYYYMMDD format.

This query investigates the records.
It does not remove or change them.
*/

with source_data as (

    select
        -- Candidate business key.
        company_code,
        order_number,
        unique_sku_code,

        -- Original date values.
        order_date as raw_order_date,
        scheduled_ship_date as raw_scheduled_ship_date,
        customer_requested_date as raw_customer_requested_date,
        revised_delivery_date as raw_revised_delivery_date,

        -- Proposed date conversions.
        try_to_date(
            order_date::varchar,
            'YYYYMMDD'
        ) as converted_order_date,

        try_to_date(
            scheduled_ship_date::varchar,
            'YYYYMMDD'
        ) as converted_scheduled_ship_date,

        try_to_date(
            customer_requested_date::varchar,
            'YYYYMMDD'
        ) as converted_customer_requested_date,

        try_to_date(
            revised_delivery_date::varchar,
            'YYYYMMDD'
        ) as converted_revised_delivery_date,

        -- Metadata for tracing each record to its file.
        source_filename,
        source_file_row_number

    from {{ source('order_intelligence_raw', 'open_orders') }}

)

select *
from source_data

where
    (
        raw_order_date is not null
        and converted_order_date is null
    )
    or (
        raw_scheduled_ship_date is not null
        and converted_scheduled_ship_date is null
    )
    or (
        raw_customer_requested_date is not null
        and converted_customer_requested_date is null
    )
    or (
        raw_revised_delivery_date is not null
        and converted_revised_delivery_date is null
    )

order by
    source_filename,
    source_file_row_number