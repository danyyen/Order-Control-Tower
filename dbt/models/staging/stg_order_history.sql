/*
Purpose:
    Provide a consistent starting point for order-history analysis.

Grain:
    One row per record in the loaded source file.

Record identity:
    source_filename + source_file_row_number identifies a record
    within the current loaded file version.

Known limitation:
    Company + order + SKU is not unique.
    The meaning of repeated records and quantity revisions is
    still being investigated, so every source record is preserved.

Excluded field:
    order_amount is retained in RAW for source traceability but is
    excluded from staging because its values do not represent
    reliable business facts and must not be used as revenue.    
*/

select
    -- Business identifiers.
    -- Keep their current text types, including pseudonymized values.
    company_code,
    order_number,
    purchase_order_number,
    customer_name,

    -- Product identifiers and descriptions.
    full_sku_code,
    first_half_sku_code,
    unique_sku_code,
    product_description,
    product_category,

    -- Source classifications.
    -- Retain the codes until their meanings are confirmed.
    delivery_route,
    order_type,
    order_status,

    -- These three columns are already DATE values in current RAW.
    -- No further date parsing is needed for this source.
    order_date,
    scheduled_ship_date,
    shipped_date,

    -- Preserve the quantity fields separately.
    -- Their business definitions and revision behavior need confirmation.
    ordered_quantity,
    secondary_order_quantity,
    final_order_quantity,
    shipped_order_quantity,
    quantity_short,

    -- Preserve source measures without assuming units or currency.
    shipped_order_weight,
    

    -- Privacy-processing flags reported by the upstream pipeline.
    -- These flags record processing outcomes; they are not identifiers.
    original_product_description_removed,
    original_product_category_removed,
    original_customer_name_removed,
    original_sku_codes_removed,
    original_purchase_order_number_removed,
    original_company_code_removed,

    -- Keep the original source batch ID.
    -- It can differ from the processing-run ID in the filename.
    batch_id,

    -- Existing content hash; it is not unique for every source record.
    row_hash,

    -- Rename timestamps to make their pipeline stages clearer.
    ingested_at_datetime as source_ingested_at,
    standardized_at,
    pseudonymized_at,

    -- File metadata lets us trace a record back to its source.
    source_filename,
    source_file_row_number,
    source_file_last_modified,

    -- This is when Snowflake scanned the file during loading.
    ingested_at as snowflake_loaded_at

from {{ source('order_intelligence_raw', 'order_history') }}