-- Return any source positions that appear more than once.
-- A passing test returns zero rows.
-- Neither column needs to be unique by itself; the pair must be unique.

select
    source_filename,
    source_file_row_number,
    count(*) as records_at_position

from {{ ref('stg_order_history') }}

group by
    source_filename,
    source_file_row_number

having count(*) > 1