-- Exclude summary rows from the expected population.
-- Works whether a Grand Total row is present or absent.
with expected as (
    select count(*) as row_count
    from {{ source('order_intelligence_raw', 'inventory') }}
    where pallet_number is not null
),

actual as (
    select count(*) as row_count
    from {{ ref('stg_inventory') }}
)

select
    expected.row_count as expected_rows,
    actual.row_count as actual_rows
from expected
cross join actual
where expected.row_count <> actual.row_count