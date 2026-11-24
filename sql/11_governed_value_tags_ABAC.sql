--Step 1: governed value tags and policy enforce.
--1. Re-apply the tag, so it's definitely set under the governed definition (harmless if it already was)
-- One-time re-apply on 2026-11-24; the SET below is enough on a re-run.
-- ALTER TABLE retail.bronze.transactions ALTER COLUMN customer_id UNSET TAGS ('pii');
ALTER TABLE retail.bronze.transactions ALTER COLUMN customer_id SET TAGS ('pii' = 'pseudonymous_id');

SELECT column_name, tag_name, tag_value
FROM retail.information_schema.column_tags
WHERE tag_name = 'pii';

--2. Negative test: does the governed tag refuse a bad value:
-- Expect an ERROR: 'test' is not an allowed value for governed tag pii
-- Negative test, run once: refused with UC_TAG_POLICY_VALUE_NOT_ALLOWED.
-- ALTER TABLE retail.bronze.transactions ALTER COLUMN country SET TAGS ('pii' = 'test');

--Step 2: the ABAC policy.
--DROP POLICY mask_pii_pseudonymous ON SCHEMA retail.bronze;

CREATE POLICY mask_pii_pseudonymous
ON SCHEMA retail.bronze
COMMENT 'Mask any column tagged pii = pseudonymous_id for everyone except pii_readers (D012)'
COLUMN MASK retail.governance.mask_pseudonymous_id
TO `account users` EXCEPT `pii_readers`
FOR TABLES
MATCH COLUMNS has_tag_value('pii', 'pseudonymous_id') AS c
ON COLUMN c;

-- List the policies on a schema
SHOW POLICIES ON SCHEMA retail.bronze;

-- Show one policy's details: function, conditions, who it applies to
DESCRIBE POLICY mask_pii_pseudonymous ON SCHEMA retail.bronze;

-- 1. Remove the per-column mask; the policy should take over
-- One-time migration on 2026-11-24 from per-column mask to ABAC policy (D017).
-- ALTER TABLE retail.bronze.transactions ALTER COLUMN customer_id DROP MASK;

-- 2. As a pii_readers member: expect real IDs (17841, 14911, ...)
SELECT customer_id, COUNT(*) AS rows
FROM retail.bronze.transactions
GROUP BY customer_id ORDER BY rows DESC LIMIT 5;

SELECT policy_name, policy_type, on_securable_type, catalog_name, schema_name,
       securable_name, to_principals, except_principals, when_condition, match_columns
FROM retail.information_schema.abac_policy_definitions;

--Step 1: check that the tag key and value are read correctly from match_columns:
SELECT p.policy_name, p.catalog_name, p.schema_name, p.securable_name AS table_name,
       regexp_extract(mc, r"has_tag_value\('([^']+)',\s*'([^']+)'\)", 1) AS tag_key,
       regexp_extract(mc, r"has_tag_value\('([^']+)',\s*'([^']+)'\)", 2) AS tag_value,
       p.except_principals
FROM retail.information_schema.abac_policy_definitions p
LATERAL VIEW explode(p.match_columns) x AS mc
WHERE p.policy_type = 'COLUMN_MASK';

--Step 2: the control itself
-- PII coverage control v2 (target: 0 rows)
-- A pii column is covered by a per-column mask, OR by a column-mask policy that
-- matches its tag value and exempts pii_readers
WITH policy_tags AS (
  SELECT p.catalog_name, p.schema_name, p.securable_name AS table_name,
         regexp_extract(mc, r"has_tag_value\('([^']+)',\s*'([^']+)'\)", 1) AS tag_key,
         regexp_extract(mc, r"has_tag_value\('([^']+)',\s*'([^']+)'\)", 2) AS tag_value
  FROM retail.information_schema.abac_policy_definitions p
  LATERAL VIEW explode(p.match_columns) x AS mc
  WHERE p.policy_type = 'COLUMN_MASK'
    AND array_contains(p.except_principals, 'pii_readers')
)
SELECT t.schema_name, t.table_name, t.column_name, t.tag_value
FROM retail.information_schema.column_tags t
LEFT ANTI JOIN retail.information_schema.column_masks m
  ON  m.table_catalog = t.catalog_name AND m.table_schema = t.schema_name
  AND m.table_name    = t.table_name   AND m.column_name  = t.column_name
LEFT ANTI JOIN policy_tags p
  ON  p.tag_key = t.tag_name AND p.tag_value = t.tag_value
  AND p.catalog_name = t.catalog_name
  AND (p.schema_name IS NULL OR p.schema_name = t.schema_name)
  AND (p.table_name  IS NULL OR p.table_name  = t.table_name)
WHERE t.tag_name = 'pii';

--Step 3: negative test. Tag a column with an allowed value that no policy covers:
--ALTER TABLE retail.bronze.transactions ALTER COLUMN country SET TAGS ('pii' = 'quasi_id');
-- rerun the control: expect 1 row (country, quasi_id). Governed tag allows it, but no policy masks quasi_id
--ALTER TABLE retail.bronze.transactions ALTER COLUMN country UNSET TAGS ('pii');
-- rerun: back to 0 rows