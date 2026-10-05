with expected as (
    select *
    from {{ source('order_intelligence_raw', 'inventory') }}
    where pallet_number is not null
),

actual as (
    select *
    from {{ ref('stg_inventory') }}
)

select
    coalesce(r.source_filename, s.source_filename) as source_filename,
    coalesce(
        r.source_file_row_number,
        s.source_file_row_number
    ) as source_file_row_number
from expected r
full outer join actual s
    on r.source_filename = s.source_filename
   and r.source_file_row_number = s.source_file_row_number
where r.source_filename is null
   or s.source_filename is null
   or r.reserved_quantity is distinct from s.reserved_quantity
   or r.quantity_on_hand is distinct from s.quantity_on_hand
   or r.weight is distinct from s.weight
   or try_to_date(
          r.snapshot_date::number(8, 0)::varchar, 'YYYYMMDD'
      ) is distinct from s.snapshot_date
   or try_to_date(
          r.production_date::number(8, 0)::varchar, 'YYYYMMDD'
      ) is distinct from s.production_date
   or try_to_date(
          r.best_before_date::number(8, 0)::varchar, 'YYYYMMDD'
      ) is distinct from s.best_before_date