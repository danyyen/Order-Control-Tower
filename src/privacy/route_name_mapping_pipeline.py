"""
src/privacy/route_name_mapping_pipeline.py

Stage: assign stable pseudo route names to every distinct delivery_route_name
value in the latest standardized open orders file, preserving pseudo names
already assigned in route_name_mapping_final.csv and only generating new
ones for route names that haven't been seen before.

Unlike customer/product, delivery_route_name is open-orders-only — order
history has no equivalent field (it only carries the numeric
delivery_route code, which stays unmasked per current policy) — so this
mapping doesn't need the shared-foundation/backfill machinery that
customer and product identity use. It's a self-contained profile+assign
pipeline, same pattern as profile_customers.py + customer_mapping_pipeline.py
combined into one stage since there's only one source to profile.

WHY THIS EXISTS: delivery_route_name is free text describing a physical
route, and in practice that text frequently embeds a real customer name
and city/province (e.g. "COSTCO - AIRDRIE (AB)"), which is a more direct
identity leak than the numeric route code ever was. delivery_route itself
is left unmasked by deliberate choice (see docs/DECISIONS.md) — this
script only touches delivery_route_name.

Output contract:
    data/metadata/route_name_mapping_final.csv
"""

from __future__ import annotations

import logging
import os
import sys
from pathlib import Path

import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from config.paths import STANDARDIZED_DIR, METADATA_DIR

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    stream=sys.stdout,
)
logger = logging.getLogger("route_name_mapping_pipeline")

FINAL_COLUMNS = ["delivery_route_name", "pseudo_delivery_route_name"]
PSEUDO_PREFIX = "Route RT-"


def find_input_file() -> Path:
    candidates = sorted(STANDARDIZED_DIR.glob("open_orders_standardized_*.csv"))
    if not candidates:
        raise FileNotFoundError(
            f"No files matching 'open_orders_standardized_*.csv' found in "
            f"{STANDARDIZED_DIR}. Run standardize_open_orders_columns.py first."
        )
    return candidates[-1]


def atomic_write_csv(df: pd.DataFrame, output_file: Path) -> None:
    tmp_file = output_file.with_suffix(output_file.suffix + ".tmp")
    df.to_csv(tmp_file, index=False, encoding="utf-8-sig")
    os.replace(tmp_file, output_file)


def main() -> int:
    METADATA_DIR.mkdir(parents=True, exist_ok=True)
    route_mapping_file = METADATA_DIR / "route_name_mapping_final.csv"

    try:
        input_file = find_input_file()
        logger.info(f"Reading: {input_file}")

        orders = pd.read_csv(input_file, dtype=str)
        orders.columns = orders.columns.str.strip().str.lower().str.replace(" ", "_")

        if orders.empty:
            raise ValueError(f"{input_file.name} has 0 rows. Refusing to profile an empty file.")

        if "delivery_route_name" not in orders.columns:
            raise ValueError(
                "Open orders file is missing required column: delivery_route_name"
            )

        distinct_routes = (
            orders["delivery_route_name"]
            .dropna()
            .astype(str)
            .str.strip()
            .drop_duplicates()
            .sort_values()
            .reset_index(drop=True)
        )
        logger.info(f"Distinct delivery_route_name values in source: {len(distinct_routes):,}")

        # --- Load existing mapping if it exists ---
        if route_mapping_file.exists():
            existing_mapping = pd.read_csv(route_mapping_file, dtype=str)
            existing_mapping.columns = (
                existing_mapping.columns.str.strip().str.lower().str.replace(" ", "_")
            )

            missing_existing = [c for c in FINAL_COLUMNS if c not in existing_mapping.columns]
            if missing_existing:
                raise ValueError(
                    f"route_name_mapping_final.csv is missing required column(s): {missing_existing}"
                )

            existing_mapping["delivery_route_name"] = (
                existing_mapping["delivery_route_name"].astype(str).str.strip()
            )
            logger.info(f"Loaded existing route mapping: {len(existing_mapping):,}")
        else:
            existing_mapping = pd.DataFrame(columns=FINAL_COLUMNS)
            logger.info("No existing route name mapping found.")

        # --- Identify new route names ---
        existing_names = set(existing_mapping["delivery_route_name"])
        new_routes = distinct_routes[~distinct_routes.isin(existing_names)]
        logger.info(f"New route name(s) found: {len(new_routes):,}")

        if len(new_routes) > 0:
            if len(existing_mapping) > 0:
                existing_seq = (
                    existing_mapping["pseudo_delivery_route_name"]
                    .str.extract(r"(\d+)$")[0]
                    .astype(float)
                )
                if existing_seq.isna().all():
                    raise ValueError(
                        "Could not determine the next route sequence number: every "
                        "existing pseudo_delivery_route_name failed to match the "
                        f"expected trailing-digit pattern (e.g. '{PSEUDO_PREFIX}000123'). "
                        "Check route_name_mapping_final.csv for corruption or manual "
                        "edits that broke the naming format."
                    )
                start_num = int(existing_seq.max()) + 1
            else:
                start_num = 1

            new_mapping = pd.DataFrame({
                "delivery_route_name": new_routes.values,
            })
            new_mapping["route_sequence"] = range(start_num, start_num + len(new_mapping))
            new_mapping["pseudo_delivery_route_name"] = (
                PSEUDO_PREFIX + new_mapping["route_sequence"].astype(str).str.zfill(6)
            )
            new_mapping = new_mapping[FINAL_COLUMNS]
        else:
            new_mapping = pd.DataFrame(columns=FINAL_COLUMNS)

        # --- Combine existing + new ---
        final_mapping = pd.concat(
            [existing_mapping[FINAL_COLUMNS], new_mapping[FINAL_COLUMNS]],
            ignore_index=True,
        )

        # --- Quality checks ---
        duplicate_keys = final_mapping["delivery_route_name"].duplicated().sum()
        if duplicate_keys > 0:
            raise ValueError(f"Duplicate delivery_route_name values found: {duplicate_keys}")

        missing_pseudo = final_mapping["pseudo_delivery_route_name"].isna().sum()
        if missing_pseudo > 0:
            raise ValueError(f"Missing pseudo route names: {missing_pseudo}")

        duplicate_pseudo = final_mapping["pseudo_delivery_route_name"].duplicated().sum()
        if duplicate_pseudo > 0:
            raise ValueError(
                f"Duplicate pseudo_delivery_route_name values found: {duplicate_pseudo} "
                f"(two different real route names would collide onto one pseudonym)."
            )

        # --- Export ---
        atomic_write_csv(final_mapping, route_mapping_file)

        logger.info(f"Route name mapping saved: {len(final_mapping):,} route names")
        logger.info(str(route_mapping_file))

        return 0

    except Exception:
        logger.exception("Route name mapping pipeline failed")
        return 1


if __name__ == "__main__":
    sys.exit(main())
