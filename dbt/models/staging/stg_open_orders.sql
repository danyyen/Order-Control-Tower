/*
Purpose:
    Prepare the current open-orders extract for downstream analysis.

Source meaning:
    OPEN_ORDERS contains orders at the ready-to-pick stage at the
    time of the extract. It does not contain every stage in the
    order lifecycle.

Grain:
    One ready-to-pick order-product record in the current source file.

Candidate business key:
    company_code + order_number + unique_sku_code

    This combination is populated and unique for the current 6,355
    records. It remains a candidate key until the source-system
    contract confirms that it is always unique.

Technical source key:
    source_filename + source_file_row_number

Date rule:
    Valid YYYYMMDD values are converted to DATE.
    A source value of 0 is treated as an unavailable date and becomes NULL.
    Six current records contain 0 in all four date fields.

Important lifecycle limitation:
    A record disappearing from a later open-orders extract does not
    by itself prove that the order shipped or completed.

Excluded field:
    order_amount is excluded because all 6,355 source values were
    verified as zero and the field is not suitable for analysis.
*/

with source as (

    -- source() tells dbt where this existing RAW table lives
    -- and adds it to the project's lineage.
    select *
    from {{ source('order_intelligence_raw', 'open_orders') }}

),

renamed_and_standardized as (

    select
        -- Business identifiers.
        company_code,
        customer_name,
        purchase_order_number,

        -- ORDER_NUMBER is an identifier rather than a quantity.
        -- Text prevents downstream users from treating it as a measure.
        order_number::varchar as order_number,

        -- Source classifications.
        -- These are codes, so text better reflects their purpose.
        order_type,
        order_status::varchar as order_status,

        -- Product identifiers and descriptions.
        full_sku_code,
        first_half_sku_code,
        unique_sku_code,
        product_description,
        product_category,
        product_category_derived,

        -- Delivery-route fields.
        delivery_route_name,
        delivery_route::varchar as delivery_route,

        -- Convert YYYYMMDD numbers into real dates.
        --
        -- NULLIF(value, 0) changes the source placeholder 0 to NULL.
        -- TRY_TO_DATE converts valid values without stopping the entire
        -- model if a future file contains another invalid date.
        -- An automated test will detect unexpected invalid values.
        try_to_date(
            nullif(order_date, 0)::varchar,
            'YYYYMMDD'
        ) as order_date,

        try_to_date(
            nullif(scheduled_ship_date, 0)::varchar,
            'YYYYMMDD'
        ) as scheduled_ship_date,

        try_to_date(
            nullif(customer_requested_date, 0)::varchar,
            'YYYYMMDD'
        ) as customer_requested_date,

        try_to_date(
            nullif(revised_delivery_date, 0)::varchar,
            'YYYYMMDD'
        ) as revised_delivery_date,

        -- Preserve source quantities and weights unchanged.
        -- Their units and detailed business definitions still
        -- need confirmation.
        final_order_quantity,
        shipped_order_quantity,
        estimated_order_weight,
        shipped_order_weight,

        -- Original source batch identifier.
        batch_id,

        -- Upstream privacy-processing flags.
        original_product_description_removed,
        original_customer_name_removed,
        original_sku_codes_removed,
        original_delivery_route_name_removed,
        original_purchase_order_number_removed,
        original_company_code_removed,

        -- Upstream content hash.
        -- This is retained for traceability but is not currently
        -- declared as the business key.
        row_hash,

        -- Rename processing timestamps to distinguish their stages.
        ingested_at_datetime as source_ingested_at,
        standardized_at,
        pseudonymized_at,

        -- Snowflake file metadata.
        source_filename,
        source_file_row_number,
        source_file_last_modified,

        -- Snowflake file-scan timestamp.
        ingested_at as snowflake_loaded_at

    from source

)

select *
from renamed_and_standardized