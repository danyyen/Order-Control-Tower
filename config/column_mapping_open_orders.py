"""
config/column_mapping_open_orders.py

Source column codes -> readable names, specific to the "Open Orders"
sheet. This is intentionally separate from column_mapping.py (order
history) because several codes here don't exist in that mapping, and
this sheet carries a redundant, fragile-format duplicate of the
scheduled ship date that is dropped rather than mapped.

The codes below are generic placeholders that describe the shape of the
export. The codes used by an actual source system are deployment
settings: put them in config/local_overrides.py (not committed) and they
replace the placeholders automatically.
"""

COLUMN_MAPPING_OPEN_ORDERS = {
    "comp_cd": "company_code",
    "src_cust_cd": "source_customer_code",
    "ship_cust_cd": "ship_to_customer_code",
    "ship_cust_nm": "customer_name",
    "po_no": "purchase_order_number",
    "ord_no": "order_number",
    "ord_dt": "order_date",
    "sched_ship_dt": "scheduled_ship_date",
    "ord_status": "order_status",
    "sku_prefix": "first_half_sku_code",
    "sku_item": "unique_sku_code",
    "item_desc": "product_description",
    "final_qty": "final_order_quantity",
    "ship_qty": "shipped_order_quantity",
    "ord_type": "order_type",
    "est_wt": "estimated_order_weight",
    "route_nm": "delivery_route_name",
    "route_cd": "delivery_route",
    "req_dt": "customer_requested_date",
    "rev_dlv_dt": "revised_delivery_date",
    "ship_wt": "shipped_order_weight",
    "sku_full": "full_sku_code",
    "ord_amt": "order_amount",
    "batch_id": "batch_id",
    "ingested_at": "ingested_at_datetime",
}

# Columns intentionally excluded from the pipeline entirely (not renamed,
# not carried forward) — documented here so it's a deliberate decision,
# not something silently missed:
#   sched_ship_dt_alt - redundant duplicate of sched_ship_dt, stored in a
#                       fragile digit-concatenated format with no leading
#                       zeros. Confirmed identical across sample rows.
#   ord_val           - confirmed not needed.
#   created_by        - confirmed not relevant for open orders (unlike
#                       order history, where the equivalent field is kept).
DROP_COLUMNS_OPEN_ORDERS = ["sched_ship_dt_alt", "ord_val", "created_by"]

# Deployment-specific codes, when present, replace the placeholders above.
# Only a missing file is tolerated: a local_overrides.py that exists but
# is incomplete or broken fails loudly instead of silently falling back.
try:
    from config.local_overrides import (  # noqa: F401,F811
        COLUMN_MAPPING_OPEN_ORDERS,
        DROP_COLUMNS_OPEN_ORDERS,
    )
except ModuleNotFoundError:
    pass
