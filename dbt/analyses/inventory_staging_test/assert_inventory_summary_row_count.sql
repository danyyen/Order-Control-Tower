-- Each file may contain zero or one summary row.
select
    source_filename,
    count(*) as missing_pallet_rows
from {{ source('order_intelligence_raw', 'inventory') }}
where pallet_number is null
group by source_filename
having count(*) > 1