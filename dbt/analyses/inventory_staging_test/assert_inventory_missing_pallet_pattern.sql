-- Flag missing-pallet rows that differ from the observed summary pattern.
select
    source_filename,
    source_file_row_number,
    full_sku_code,
    lot_number,
    slot_location,
    reserved_quantity,
    quantity_on_hand,
    weight
from {{ source('order_intelligence_raw', 'inventory') }}
where pallet_number is null
  and (
      lot_number is not null
      or slot_location is not null
      or reserved_quantity is not null
      or quantity_on_hand is null
      or weight is null
  )