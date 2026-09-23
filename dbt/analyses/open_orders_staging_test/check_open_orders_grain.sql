/*
Purpose:
    Evaluate possible identifiers for open-orders records.

Candidate business key:
    company_code + order_number + unique_sku_code

Technical source key:
    source_filename + source_file_row_number

This query investigates the current data.
It does not permanently declare either combination to be a business key.
*/

with source_data as (

    select
        company_code,
        order_number,
        unique_sku_code,
        source_filename,
        source_file_row_number

    from {{ source('order_intelligence_raw', 'open_orders') }}

),

business_key_groups as (

    select
        company_code,
        order_number,
        unique_sku_code,
        count(*) as rows_per_business_key

    from source_data

    group by
        company_code,
        order_number,
        unique_sku_code

),

source_position_groups as (

    select
        source_filename,
        source_file_row_number,
        count(*) as rows_per_source_position

    from source_data

    group by
        source_filename,
        source_file_row_number

)

select
    count(*) as total_rows,

    -- A business key cannot identify a record if part of it is missing.
    count_if(
        company_code is null
        or trim(company_code) = ''
    ) as missing_company_codes,

    count_if(
        order_number is null
    ) as missing_order_numbers,

    count_if(
        unique_sku_code is null
        or trim(unique_sku_code) = ''
    ) as missing_unique_sku_codes,

    -- How many candidate business-key combinations repeat?
    (
        select count_if(rows_per_business_key > 1)
        from business_key_groups
    ) as duplicate_business_key_groups,

    -- Metadata is required to trace records to their source file.
    count_if(
        source_filename is null
        or source_file_row_number is null
    ) as rows_missing_source_metadata,

    -- Source file positions should identify individual loaded records.
    (
        select count_if(rows_per_source_position > 1)
        from source_position_groups
    ) as duplicate_source_positions

from source_data