# Snowflake?dbt connection setup: beginner knowledge note

Connection success reported by the user on September 17, 2026.
This records the completed setup, not instructions to recreate or replace keys.
No passwords, passphrases, or key contents are stored in this note.

## The big picture

- **Snowflake** stores the data and executes SQL using a compute warehouse.
- **dbt web app** is where we develop, test, and run transformation code.
- **GitHub** stores that code and its change history, not the Snowflake tables.
- **Authentication** asks ?Who are you?? We used a key pair for the Snowflake user.
- **Authorization** asks ?What can you do?? Snowflake roles supply permissions.
- A successful connection does not mean staging models have been built or all
  future dbt operations tested. It establishes the connection needed to start.

## Step-by-step summary: what we did and why

- **1. Confirmed the RAW sources existed.**
  - ORDER_HISTORY, OPEN_ORDERS, and INVENTORY live in ORDER_INTELLIGENCE_DB.RAW.
  - Connecting dbt does not upload S3 files or reload these tables.

- **2. Created a separate development schema in Snowsight.**
  - Name: ORDER_INTELLIGENCE_DB.DBT_DANYYEN.
  - A schema is a folder-like namespace inside a database.
  - dbt reads RAW and builds development models in DBT_DANYYEN.
  - Separating input and output keeps development from overwriting source tables.

- **3. Created a transformation role.**
  - Name: ORDER_INTELLIGENCE_TRANSFORMER.
  - Granted it to DANYYEN and to SYSADMIN in the role hierarchy.
  - Granted USAGE on the database, warehouse, RAW schema, and development schema.
  - USAGE permits access to the container/resource; it does not alone permit reading rows.
  - Granted SELECT on existing and future RAW tables.
  - Granted CREATE TABLE and CREATE VIEW in DBT_DANYYEN.
  - Existing-table grants cover today?s tables; future grants cover tables created later.
  - Used SYSADMIN/SECURITYADMIN for administration; dbt uses the transformer role.

- **4. Verified read access as the transformer role.**
  - Ran a COUNT(*) query against RAW.OPEN_ORDERS and received 6,355 rows.
  - This tested RAW read permission, not every possible dbt write operation.

- **5. Named the dbt project.**
  - Project name: order_intelligence.
  - A dbt project groups SQL models, tests, documentation, and configuration.

- **6. Created the Snowflake connection in dbt.**
  - Connection name: order_intelligence_snowflake.
  - Account: EXDSXDU-CV04446 (without https:// or .snowflakecomputing.com).
  - Database: ORDER_INTELLIGENCE_DB.
  - Warehouse: ORDER_INTELLIGENCE_WH.
  - Intended role: ORDER_INTELLIGENCE_TRANSFORMER.
  - The database stores objects; the warehouse supplies compute to run queries.
  - Saving the connection only saves settings; it does not establish successful login.

- **7. Attached the connection to the development environment.**
  - Initially ?0 environments? meant no environment used the saved connection yet.
  - Selected the connection under Configure your development environment.
  - An environment groups the connection, credentials, and runtime settings for work.

- **8. Selected personal development settings.**
  - Username: DANYYEN.
  - Schema: DBT_DANYYEN, replacing the automatically suggested dbt_dfyne.
  - Target name: dev, a label for this development configuration.
  - Threads: 4, allowing up to four concurrent model-execution threads.
  - Personal development credentials are separate from future production-job credentials.

- **9. Connected the existing GitHub repository.**
  - Repository: danyyen/Order-Control-Tower.
  - Chose GitHub so the project can use commits, branches, and pull requests.
  - Repository access and Snowflake access are two separate connections.
  - A dbt subfolder was proposed but its creation/configuration has not been confirmed.
  - Before initialization, decide the project location and configure the project
    subdirectory if dbt_project.yml will not be at the repository root.

- **10. Diagnosed the password authentication error.**
  - Snowflake explicitly reported that password login required a current TOTP code.
  - The dbt form used did not supply that code, so username/password testing failed.
  - This was an authentication issue, not evidence that RAW data or table grants were wrong.
  - We chose the available Key pair method rather than disabling MFA.

- **11. Generated an encrypted RSA key pair locally.**
  - OpenSSL was unavailable; the installed Python cryptography library was available.
  - Created src/warehouse/generate_dbt_keys.py as a reusable, commented helper.
  - Ran: python src/warehouse/generate_dbt_keys.py.
  - The helper prompts for a new passphrase twice without showing the typing.
  - Its minimum is 16 characters; the first shorter entry created no files.
  - It generates a 2048-bit RSA key and an encrypted PKCS#8 private-key file.
  - It refuses to overwrite its existing output folder. Do not regenerate keys for normal login.

- **12. Stored the keys outside the repository.**
  - Folder: C:/Users/ND/.snowflake/order_intelligence_dbt/.
  - rsa_key.pub: public key, registered in Snowflake.
  - rsa_key.p8: encrypted private key, supplied to dbt?s credential form.
  - Passphrase: the new secret chosen during generation, not the Snowflake password.
  - The helper does not save the passphrase. Keep it in your password manager.
  - Key files are credentials and should not be committed to Git or pasted into chat.

- **13. Checked existing Snowflake key slots before registration.**
  - Ran DESCRIBE USER DANYYEN in Snowsight.
  - RSA_PUBLIC_KEY_FP and RSA_PUBLIC_KEY_2_FP were both NULL.
  - A fingerprint is a short identifier for a registered public key, not its contents.
  - Checking first avoided overwriting an existing authentication key.

- **14. Registered the public key on the Snowflake user.**
  - Copied rsa_key.pub without its BEGIN/END lines or line breaks.
  - Used an authorized administrator session in Snowsight to run:
    ALTER USER DANYYEN SET RSA_PUBLIC_KEY = '<public key text>';
  - The placeholder represents public-key text, not a password or passphrase.
  - This assigns the public key to the user; it does not change the user?s roles,
    disable MFA, or alter RAW data.

- **15. Entered the private key in dbt.**
  - Selected Key pair authentication.
  - Copied the complete rsa_key.p8 file, including BEGIN/END ENCRYPTED PRIVATE KEY lines.
  - Pasted it directly into dbt?s Private key field.
  - Entered the chosen key passphrase in Private key passphrase.
  - Snowflake uses the public key to verify proof made with the matching private key.
    The private key itself is not registered in Snowflake.

- **16. Tested the connection successfully.**
  - Clicked Test connection; the user reported completion.
  - This milestone establishes development connectivity, not completion of dbt modeling.
  - Next: confirm the project directory, initialize dbt, declare RAW sources,
    and build/test one staging view before expanding the project.

## Clear the clipboard after copying the private key

- The clipboard is temporary storage used by Copy and Paste.
- You do not need to know its current contents to replace them.
- In PowerShell, run this exact command; the two quotes contain nothing:

```powershell
Set-Clipboard -Value ""
```

- `-Value` names the parameter. `""` supplies an empty string, not a placeholder.
- This replaces the current clipboard text. It does not remove the saved key
  files or erase credentials already stored in dbt.
- If Windows clipboard history is enabled, also press Windows+V and choose
  Clear all. Delete any pinned key entry separately; Clear all retains pinned items.
- Alternatively: Settings > System > Clipboard > Clear clipboard data > Clear.
- No need to enable clipboard history if it was disabled. Other clipboard
  managers, if installed, have their own history controls.

## Interview explanation

- ?I connected dbt to Snowflake using encrypted RSA key-pair authentication.
  A dedicated transformation role reads RAW sources and creates models in a
  separate development schema. GitHub tracks the code. I tested source access
  and the connection separately, then planned to build and test staging models.?
- Remember the distinction: authentication verifies identity; authorization
  determines access; model tests check data assumptions. Passing one does not
  establish that the others are correct.

## Official references

- [dbt Snowflake connection and key pairs](https://docs.getdbt.com/docs/platform/connect-data-platform/connect-snowflake)
- [Snowflake key-pair authentication](https://docs.snowflake.com/en/user-guide/key-pair-auth)
- [dbt Git configuration](https://docs.getdbt.com/docs/platform/git/configure-git)
- [PowerShell Set-Clipboard](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/set-clipboard)
- [Windows clipboard and history](https://support.microsoft.com/en-au/windows/using-the-clipboard-30375039-ce71-9fe4-5b30-21b7aab6b13f)
