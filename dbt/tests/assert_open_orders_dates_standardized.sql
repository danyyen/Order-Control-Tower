/*
Protect the approved date rules:

1. Source 0 becomes staging NULL.
2. Valid YYYYMMDD becomes the corresponding DATE.
3. A future non-zero invalid date causes this test to fail.
4. Every source record must match a staging record.
*/

with raw as (

    select
        source_filename,
        source_file_row_number,
        order_date,
        scheduled_ship_date,
        customer_requested_date,
        revised_delivery_date

    from {{ source('order_intelligence_raw', 'open_orders') }}

),

staging as (

    select
        source_filename,
        source_file_row_number,
        order_date,
        scheduled_ship_date,
        customer_requested_date,
        revised_delivery_date

    from {{ ref('stg_open_orders') }}

)

select
    coalesce(
        raw.source_filename,
        staging.source_filename
    ) as source_filename,

    coalesce(
        raw.source_file_row_number,
        staging.source_file_row_number
    ) as source_file_row_number

from raw

full outer join staging
    on raw.source_filename = staging.source_filename
    and raw.source_file_row_number = staging.source_file_row_number

where
    -- A record is missing from one side.
    raw.source_filename is null
    or staging.source_filename is null

    -- A future non-zero source value cannot be converted.
    or (
        raw.order_date is not null
        and raw.order_date <> 0
        and try_to_date(raw.order_date::varchar, 'YYYYMMDD') is null
    )
    or (
        raw.scheduled_ship_date is not null
        and raw.scheduled_ship_date <> 0
        and try_to_date(
            raw.scheduled_ship_date::varchar,
            'YYYYMMDD'
        ) is null
    )
    or (
        raw.customer_requested_date is not null
        and raw.customer_requested_date <> 0
        and try_to_date(
            raw.customer_requested_date::varchar,
            'YYYYMMDD'
        ) is null
    )
    or (
        raw.revised_delivery_date is not null
        and raw.revised_delivery_date <> 0
        and try_to_date(
            raw.revised_delivery_date::varchar,
            'YYYYMMDD'
        ) is null
    )

    -- The staging value differs from the expected conversion.
    or staging.order_date is distinct from
        try_to_date(
            nullif(raw.order_date, 0)::varchar,
            'YYYYMMDD'
        )

    or staging.scheduled_ship_date is distinct from
        try_to_date(
            nullif(raw.scheduled_ship_date, 0)::varchar,
            'YYYYMMDD'
        )

    or staging.customer_requested_date is distinct from
        try_to_date(
            nullif(raw.customer_requested_date, 0)::varchar,
            'YYYYMMDD'
        )

    or staging.revised_delivery_date is distinct from
        try_to_date(
            nullif(raw.revised_delivery_date, 0)::varchar,
            'YYYYMMDD'
        )