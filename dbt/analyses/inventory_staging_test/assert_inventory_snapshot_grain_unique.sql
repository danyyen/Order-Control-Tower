-- A pallet may recur across weeks, but only once per warehouse snapshot.
select
    snapshot_date,
    warehouse_code,
    pallet_number,
    count(*) as records
from {{ ref('stg_inventory') }}
group by
    snapshot_date,
    warehouse_code,
    pallet_number
having count(*) > 1