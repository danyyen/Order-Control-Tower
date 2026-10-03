"""
config/column_mapping.py

Source column codes -> readable names for the "Order History" sheet.

The codes below are generic placeholders that describe the shape of the
export. The codes used by an actual source system are deployment
settings: put them in config/local_overrides.py (not committed) and they
replace the placeholders automatically. Without that file, the pipeline
expects a workbook whose headers match the placeholders below.
"""

COLUMN_MAPPING = {
    "comp_cd": "company_code",
    "src_cust_cd": "source_customer_code",
    "ship_cust_cd": "ship_to_customer_code",
    "ship_cust_nm": "customer_name",
    "po_no": "purchase_order_number",
    "ord_no": "order_number",
    "ord_type": "order_type",
    "ord_dt": "order_date",
    "sched_ship_dt": "scheduled_ship_date",
    "ship_dt": "shipped_date",
    "created_by": "created_by_user",
    "route_cd": "delivery_route",
    "ord_status": "order_status",
    "ord_qty": "ordered_quantity",
    "sku_full": "full_sku_code",
    "sku_prefix": "first_half_sku_code",
    "sku_item": "unique_sku_code",
    "item_desc": "product_description",
    "ord_qty_2": "secondary_order_quantity",
    "final_qty": "final_order_quantity",
    "ship_qty": "shipped_order_quantity",
    "qty_short": "quantity_short",
    "ship_wt": "shipped_order_weight",
    "ord_amt": "order_amount",
    "item_cat": "product_category",
    "batch_id": "batch_id",
    "ingested_at": "ingested_at_datetime",
}

# Deployment-specific codes, when present, replace the placeholders above.
# Only a missing file is tolerated: a local_overrides.py that exists but
# is incomplete or broken fails loudly instead of silently falling back.
try:
    from config.local_overrides import COLUMN_MAPPING  # noqa: F401,F811
except ModuleNotFoundError:
    pass
