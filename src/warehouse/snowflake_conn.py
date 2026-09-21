"""Open a Snowflake session using settings from this terminal's environment.

Required: SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_PASSWORD.
Optional: SNOWFLAKE_PASSCODE (a fresh MFA code), SNOWFLAKE_ROLE,
SNOWFLAKE_WAREHOUSE, SNOWFLAKE_DATABASE, and SNOWFLAKE_SCHEMA.
The defaults below point at this project's loader role and RAW schema.

os.environ reads environment variables; it does not load a .env file.
Keep passwords out of source code and refresh the TOTP for each new login.
This helper uses the password/passcode method verified for this project.
It does not configure key-pair authentication or browser SSO.
See snowflake/README.md for PowerShell instructions.
"""
from __future__ import annotations

import os

import snowflake.connector


def get_snowflake_connection() -> snowflake.connector.SnowflakeConnection:
    # Fail locally with the missing setting names before contacting Snowflake.
    required = ["SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER", "SNOWFLAKE_PASSWORD"]
    missing = [v for v in required if not os.environ.get(v)]
    if missing:
        raise RuntimeError(
            f"Missing required environment variable(s): {missing}. Set them in "
            f"your own shell before running this script — never hardcode "
            f"credentials here or pass them as command-line arguments."
        )

    # These are session defaults; the loaders use RAW-qualified object names.
    connect_kwargs = dict(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        password=os.environ["SNOWFLAKE_PASSWORD"],
        role=os.environ.get("SNOWFLAKE_ROLE", "ORDER_INTELLIGENCE_LOADER"),
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "ORDER_INTELLIGENCE_WH"),
        database=os.environ.get("SNOWFLAKE_DATABASE", "ORDER_INTELLIGENCE_DB"),
        schema=os.environ.get("SNOWFLAKE_SCHEMA", "RAW"),
    )

    # Keep the MFA code separate from the password; never log either value.
    passcode = os.environ.get("SNOWFLAKE_PASSCODE")
    if passcode:
        connect_kwargs["passcode"] = passcode

    return snowflake.connector.connect(**connect_kwargs)
