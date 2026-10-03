"""Create encrypted credentials for dbt; does not connect to Snowflake.

Run this yourself in an interactive terminal so only you enter the passphrase.
The script is safe to keep in Git. The generated keys belong outside the repo.
"""
from getpass import getpass
from pathlib import Path
import warnings

from getpass import GetPassWarning
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa


def main():
    # A new folder prevents accidentally replacing credentials already in use.
    key_dir = Path.home() / ".snowflake" / "order_intelligence_dbt"
    if key_dir.exists():
        raise SystemExit(f"Folder already exists: {key_dir}. No keys were overwritten.")

    # Stop if the terminal cannot hide input instead of echoing the passphrase.
    warnings.simplefilter("error", GetPassWarning)
    passphrase = getpass("Choose a NEW private-key passphrase (input hidden): ")
    if len(passphrase) < 16:
        raise SystemExit("Please choose a passphrase of at least 16 characters.")
    if passphrase != getpass("Enter it again: "):
        raise SystemExit("Passphrases did not match. No files were created.")

    # RSA creates two mathematically related keys. The public key can verify
    # signatures made with the private key, without revealing the private key.
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    private_pem = key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.BestAvailableEncryption(passphrase.encode("utf-8")),
    )
    public_pem = key.public_key().public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )

    # The passphrase is not saved. Exclusive creation refuses existing paths.
    key_dir.mkdir(parents=True, exist_ok=False)
    for name, contents in (("rsa_key.p8", private_pem), ("rsa_key.pub", public_pem)):
        with (key_dir / name).open("xb") as handle:
            handle.write(contents)

    print(f"Keys created in: {key_dir}")
    print("rsa_key.p8: encrypted PRIVATE key for dbt; keep it confidential.")
    print("rsa_key.pub: PUBLIC key to register with your Snowflake user.")
    print("Keep the passphrase in your password manager. It was not saved here.")
    print("No Snowflake settings or data were changed.")


if __name__ == "__main__":
    main()
