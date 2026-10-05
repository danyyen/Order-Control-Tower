select
    source_filename,
    source_file_row_number,
    count(*) as records
from {{ ref('stg_inventory') }}
group by source_filename, source_file_row_number
having count(*) > 1