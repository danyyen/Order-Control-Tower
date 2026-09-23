/*
This protects the grain observed in the current source data.

Passing this test means the combination is unique in the tested data.
It does not prove that the source system guarantees it forever.
*/

select
    company_code,
    order_number,
    unique_sku_code,
    count(*) as records_per_candidate_key

from {{ ref('stg_open_orders') }}

group by
    company_code,
    order_number,
    unique_sku_code

having count(*) > 1