/*
Inventory availability at one warehouse at each snapshot.

Grain:
    snapshot_date + warehouse_code + pallet_number

Preserve historical snapshots and source records.
Quantity on hand includes reserved quantity.
*/

select
    -- Snapshot date: numeric YYYYMMDD to calendar date.
    try_to_date(
        snapshot_date::number(8, 0)::varchar,
        'YYYYMMDD'
    ) as snapshot_date,

    warehouse_code,

    -- Remove numeric decimal formatting; expose identifier as text.
    pallet_number::number(38, 0)::varchar as pallet_number,

    full_sku_code,
    product_description,
    product_category,
    product_category_derived,

    lot_number,
    slot_location,
    pallet_held_flag,

    -- Source dates use numeric YYYYMMDD.
    try_to_date(
        production_date::number(8, 0)::varchar,
        'YYYYMMDD'
    ) as production_date,

    try_to_date(
        best_before_date::number(8, 0)::varchar,
        'YYYYMMDD'
    ) as best_before_date,

    -- Preserve source measures.
    reserved_quantity,
    quantity_on_hand,
    weight,

    -- Privacy-processing information.
    original_product_description_removed,
    original_sku_removed,
    original_warehouse_code_removed,
    row_hash,
    pseudonymized_at,

    -- Source lineage.
    source_filename,
    source_file_row_number,
    source_file_last_modified,
    ingested_at as snowflake_loaded_at

from {{ source('order_intelligence_raw', 'inventory') }}
where pallet_number is not null