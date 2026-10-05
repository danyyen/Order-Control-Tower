select
    snapshot_date,
    warehouse_code,
    count(*) as stock_records,
    count(distinct pallet_number) as distinct_pallets,
    count(distinct full_sku_code) as distinct_products,
    sum(quantity_on_hand) as quantity_on_hand,
    sum(reserved_quantity) as reserved_quantity,
    sum(weight) as total_weight
from {{ ref('stg_inventory') }}
group by snapshot_date, warehouse_code
order by snapshot_date desc
