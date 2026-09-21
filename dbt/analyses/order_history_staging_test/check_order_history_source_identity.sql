-- Check whether every RAW record has a distinct source-file location.
-- This identifies a record within a file, not a permanent business entity.

select
    count(*) as total_rows,

    -- Both values are required to locate a record in its source file.
    count(*) - count(source_filename) as missing_source_filenames,
    count(*) - count(source_file_row_number) as missing_source_row_numbers,

    -- Count distinct combinations without concatenating their values.
    count(distinct source_filename, source_file_row_number)
        as distinct_source_positions

from {{ source('order_intelligence_raw', 'order_history') }}