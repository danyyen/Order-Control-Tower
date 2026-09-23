# Open-orders staging decisions and business questions

## Current model purpose

`stg_open_orders` prepares the current ready-to-pick order extract
for downstream dbt models.

## Grain

Current observed grain:

> One record per company, order number, and unique SKU in the
> current open-orders extract.

The candidate business key is:

- `company_code`
- `order_number`
- `unique_sku_code`

This combination is populated and unique for the current 6,355
records. The source-system owner has not yet confirmed that this
combination is guaranteed to remain unique.

Technical source-record identity:

- `source_filename`
- `source_file_row_number`

This identifies a row within the current file version. It is not a
permanent business line identifier.

## Confirmed staging decisions

- Preserve all 6,355 source records.
- Convert four numeric YYYYMMDD fields to DATE.
- Convert source date placeholder `0` to `NULL`.
- Preserve quantities and weights without recalculation.
- Cast order number, order status, and delivery route to text.
- Retain source-file and pipeline metadata.
- Exclude `order_amount` because all current source values are zero.
- Do not infer completion from disappearance in a later extract.
- Materialize the staging model as a view.

## Date exception

Six records contain `0` in all four source date fields. These records
belong to orders 90240 and 90250 and contain valid company and SKU
identifiers.

The staging model retains the records and converts the date placeholders
to `NULL`.

The business meaning of `0` is not yet confirmed. It may mean unknown,
not scheduled, or not applicable.

## Remaining business questions

1. Is every open-orders export a complete point-in-time snapshot, or
   can it contain only changes since the previous export?

2. Does `company_code + order_number + unique_sku_code` always identify
   one open-order line? Is a source order-line identifier available?

3. What does each `order_status` value mean?

4. Does every record in this file represent the ready-to-pick stage,
   or can other stages appear?

5. What does disappearance from a later extract mean? Can it represent
   completion, cancellation, movement to another stage, or correction?

6. What is the official meaning of source date value `0`?

7. What are the definitions and units of:
   - `final_order_quantity`
   - `shipped_order_quantity`
   - `estimated_order_weight`
   - `shipped_order_weight`

8. How is `revised_delivery_date` determined, and can it change between
   snapshots?

9. Why is `order_amount` zero for every current record? Is the field
   intentionally unavailable, incorrectly extracted, or unused?

10. What timestamp or identifier should represent the business snapshot
    time? `batch_id`, source filename time, and Snowflake load time refer
    to different pipeline events.

## Downstream modeling restriction

Until the questions above are answered:

- Do not interpret disappearance as completion.
- Do not calculate revenue from `order_amount`.
- Do not assume the candidate business key is guaranteed permanently.
- Do not combine open orders with order history using only order number.
- Do not interpret pipeline timestamps as order-status timestamps.