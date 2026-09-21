-- Purpose:
-- Display every source column for records whose candidate key repeats.
-- This helps us see which values differ within each pair.

with marked_records as (

    select
        *,

        -- Count records with the same company, order, and SKU.
        -- Unlike GROUP BY, this keeps each individual record visible.
        count(*) over (
            partition by
                company_code,
                order_number,
                unique_sku_code
        ) as candidate_key_row_count

    from {{ source('order_intelligence_raw', 'order_history') }}

)

select *
from marked_records

-- Keep all records belonging to a repeated combination.
where candidate_key_row_count > 1

-- Place each pair together so we can compare their values.
order by
    company_code,
    order_number,
    unique_sku_code,
    source_filename,
    source_file_row_number