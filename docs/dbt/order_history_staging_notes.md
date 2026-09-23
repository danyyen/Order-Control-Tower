# Order-history staging decisions

## Grain

`stg_order_history` preserves one record per row in the loaded
order-history source file.

The technical source-record identifier is:

- `source_filename`
- `source_file_row_number`

Company code, order number, and unique SKU are useful for grouping,
but do not uniquely identify every source record.

## Order amount decision

`RAW.ORDER_HISTORY.ORDER_AMOUNT` is retained in RAW for auditability
and source traceability.

It is intentionally excluded from `stg_order_history` because the
values do not represent reliable business facts. The field must not
be used for revenue, sales, margin, or financial reporting.

The staging model does not replace these values with zero or null.
The field is omitted so downstream users cannot mistake it for an
approved measure.

## Requirements before reintroducing order amount

Before an order-amount measure can be exposed downstream, confirm:

1. The authoritative source of the amount.
2. Whether it represents line amount or complete order amount.
3. Its currency.
4. Whether it includes tax, discounts, freight, or adjustments.
5. Whether repeated order-history records would duplicate the amount.
6. How the amount reconciles with an approved financial source.

A future trusted amount should be introduced through a reviewed
business rule and reconciliation test.