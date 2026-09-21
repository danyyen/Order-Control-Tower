-- Purpose:
-- Find records where staging changed a source quantity.
--
-- Why:
-- Quantity meanings and revision behavior are still being investigated.
-- Our current staging contract is to preserve these values exactly.
--
-- Passing result:
-- Zero rows.

select
    raw.source_filename,
    raw.source_file_row_number,

    -- Include both versions to help investigate a failure.
    raw.ordered_quantity as raw_ordered_quantity,
    staging.ordered_quantity as staging_ordered_quantity,

    raw.secondary_order_quantity as raw_secondary_quantity,
    staging.secondary_order_quantity as staging_secondary_quantity,

    raw.final_order_quantity as raw_final_quantity,
    staging.final_order_quantity as staging_final_quantity,

    raw.shipped_order_quantity as raw_shipped_quantity,
    staging.shipped_order_quantity as staging_shipped_quantity,

    raw.quantity_short as raw_quantity_short,
    staging.quantity_short as staging_quantity_short

from {{ source('order_intelligence_raw', 'order_history') }} as raw

inner join {{ ref('stg_order_history') }} as staging
    on raw.source_filename = staging.source_filename
    and raw.source_file_row_number = staging.source_file_row_number

where
    -- IS DISTINCT FROM compares values while also handling NULL.
    -- NULL versus NULL is unchanged.
    -- NULL versus a number is a difference.
    raw.ordered_quantity
        is distinct from staging.ordered_quantity

    or raw.secondary_order_quantity
        is distinct from staging.secondary_order_quantity

    or raw.final_order_quantity
        is distinct from staging.final_order_quantity

    or raw.shipped_order_quantity
        is distinct from staging.shipped_order_quantity

    or raw.quantity_short
        is distinct from staging.quantity_short