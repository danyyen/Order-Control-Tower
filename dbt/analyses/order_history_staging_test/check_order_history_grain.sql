-- Purpose:
-- Find cases where the same company, order, and SKU appear
-- more than once. Repeated combinations need investigation;
-- they are not automatically duplicate or incorrect records.

select
    company_code,
    order_number,
    unique_sku_code,
    --shipped_order_quantity,
    -- How many source records share this combination?
    count(*) as rows_per_combination,

    -- Multiple shipping dates could help explain repeated records.
    -- COUNT(DISTINCT ...) counts different non-null values.
    count(distinct shipped_date) as distinct_shipped_dates,

    -- Show the shipping period covered by these records.
    min(shipped_date) as earliest_shipped_date,
    max(shipped_date) as latest_shipped_date

from {{ source('order_intelligence_raw', 'order_history') }}

-- Put records with the same candidate key into a group.
group by
    company_code,
    order_number,
    unique_sku_code
    --shipped_order_quantity

-- Display only combinations that appear more than once.
having count(*) > 1

-- Show the most frequently repeated combinations first.
order by
    rows_per_combination desc,
    company_code,
    order_number,
    unique_sku_code
