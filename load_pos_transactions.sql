-- Bulk-load POS transactions from GCS via COPY ... VWLOAD.
-- Supply GCS service-account credentials at runtime — do NOT hardcode them.
-- Substitute the placeholders below from your sa.json (gitignored) before running,
-- or prefer the admiral skill's sql.ps1, which injects them from sa.json for you.
SET string_truncation IGNORE;
COPY "pos_transactions"() VWLOAD
FROM 'gs://rg_gcp_test/poc_sales_detail_extract_*.csv.gz' WITH FDELIM = ',',
    RDELIM = '\n',
    QUOTE = '"',
    AUTO_DETECT_COMPRESSION,
    HEADER,
    gcs_email = '<GCS_SA_EMAIL>',
    gcs_private_key_id = '<GCS_SA_KEY_ID>',
    gcs_private_key = '<GCS_SA_PRIVATE_KEY>';
SELECT COUNT(*) AS loaded_rows FROM pos_transactions;
