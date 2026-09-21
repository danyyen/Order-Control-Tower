"""
src/privacy/hash_utils.py

Shared deterministic-hash helper for operational identifiers that must
be removed before reaching S3, but need to stay STABLE across rows and
runs so join/dedup/groupby usage keeps working (e.g. the Snowflake RAW
composite keys documented in knowledge_snowflake_raw_notes.md that
include purchase_order_number).

This is deliberately simpler than the customer/product pseudonymization
path (pseudonymize_products.py / customer_mapping_pipeline.py): those
fields get a human-readable fake identity from a persisted mapping
table because downstream consumers read them. Fields hashed here don't
need a readable replacement, only a value that is (a) not the real one
and (b) identical every time the same real value is hashed — so a
straight salted hash is sufficient and needs no mapping table.

Salt is required from the environment, not defaulted, so a missing
salt fails loudly instead of silently hashing with a guessable
built-in value.
"""

from __future__ import annotations

import hashlib
import os

import pandas as pd

SALT_ENV_VAR = "PSEUDONYMIZATION_SALT"


def _get_salt() -> str:
    salt = os.environ.get(SALT_ENV_VAR)
    if not salt:
        raise RuntimeError(
            f"{SALT_ENV_VAR} environment variable is not set. Required for "
            f"deterministic pseudonymization of operational identifiers "
            f"(purchase_order_number, warehouse_code, etc.). Set it once in "
            f"your environment/secrets store — the same salt must be reused "
            f"across runs, or the same real value will hash differently and "
            f"break downstream dedup/join logic that relies on stability."
        )
    return salt


def deterministic_hash(value) -> str | None:
    """SHA-256(value + salt), hex digest. Same input -> same output, so
    any downstream join/dedup/groupby on the hashed column behaves the
    same as it did against the raw value."""
    if pd.isna(value):
        return None
    salt = _get_salt()
    return hashlib.sha256(f"{value}{salt}".encode("utf-8")).hexdigest()


# Lowercase alphanumeric — plain-looking output, no symbols to worry about
# in a CSV/SQL context.
_PSEUDONYM_ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789"


def deterministic_pseudonym(value) -> str | None:
    """Same length as the input, characters drawn deterministically from
    a fixed alphanumeric alphabet via salted SHA-256 (extended over
    multiple rounds if the value is longer than one digest). Same real
    value -> same pseudonym always, so join/dedup/groupby usage still
    works the same as against the raw value.

    CAVEAT: exact-length output means short values have real collision
    risk — a length-1 value has only 36 possible outputs, so several
    different length-1 real values will likely land on the same
    pseudonym. This is a deliberate readability/length tradeoff against
    deterministic_hash()'s fixed 64-char output, which has effectively
    no collision risk regardless of input length. Don't use this for a
    field whose short values must stay distinguishable after masking.
    """
    if pd.isna(value):
        return None
    text = str(value)
    length = len(text)
    if length == 0:
        return text
    salt = _get_salt()
    chars: list[str] = []
    round_num = 0
    while len(chars) < length:
        digest = hashlib.sha256(f"{text}{salt}{round_num}".encode("utf-8")).digest()
        for b in digest:
            chars.append(_PSEUDONYM_ALPHABET[b % len(_PSEUDONYM_ALPHABET)])
            if len(chars) == length:
                break
        round_num += 1
    return "".join(chars)
