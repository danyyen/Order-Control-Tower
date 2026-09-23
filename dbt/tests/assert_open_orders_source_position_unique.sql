-- A passing test returns zero repeated source-file positions.

select
    source_filename,
    source_file_row_number,
    count(*) as records_at_position

from {{ ref('stg_open_orders') }}

group by
    source_filename,
    source_file_row_number

having count(*) > 1