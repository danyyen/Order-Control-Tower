/*
Staging currently promises to preserve these quantities and weights.
Their business definitions still need confirmation, but staging
must not change their values.
*/

select
    raw.source_filename,
    raw.source_file_row_number,

    raw.final_order_quantity as raw_final_order_quantity,
    staging.final_order_quantity as staging_final_order_quantity,

    raw.shipped_order_quantity as raw_shipped_order_quantity,
    staging.shipped_order_quantity as staging_shipped_order_quantity,

    raw.estimated_order_weight as raw_estimated_order_weight,
    staging.estimated_order_weight as staging_estimated_order_weight,

    raw.shipped_order_weight as raw_shipped_order_weight,
    staging.shipped_order_weight as staging_shipped_order_weight

from {{ source('order_intelligence_raw', 'open_orders') }} as raw

inner join {{ ref('stg_open_orders') }} as staging
    on raw.source_filename = staging.source_filename
    and raw.source_file_row_number = staging.source_file_row_number

where
    raw.final_order_quantity
        is distinct from staging.final_order_quantity

    or raw.shipped_order_quantity
        is distinct from staging.shipped_order_quantity

    or raw.estimated_order_weight
        is distinct from staging.estimated_order_weight

    or raw.shipped_order_weight
        is distinct from staging.shipped_order_weight