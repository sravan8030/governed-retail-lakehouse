-- 06_governance_masking.sql
CREATE SCHEMA IF NOT EXISTS retail.governance
  COMMENT 'Policy functions: column masks and row filters. Changes here change who sees what';

show schemas in retail;
describe schema extended retail.governance ;

select *
from retail.information_schema.schemata
order by created
;
select *
from retail.information_schema.tables 
order by created
;
select *
from retail.information_schema.routines 
order by created
;

CREATE OR REPLACE FUNCTION retail.governance.mask_pseudonymous_id(id STRING)
RETURNS STRING
COMMENT 'Column mask for pii = pseudonymous_id. Members of pii_readers see the value, for rest its redacted. Not hashed: 5-digit IDs are reversible by brute force'
RETURN CASE
  WHEN id IS NULL THEN NULL
  WHEN is_account_group_member('pii_readers') THEN id
  ELSE '*****'
END;

-- Superseded on 2026-11-24 by ABAC policy mask_pii_pseudonymous (D017). Re-attaching this per-column mask
-- would put two masks on customer_id. Kept as a record of the 15 Nov design.
-- ALTER TABLE retail.bronze.transactions
--   ALTER COLUMN customer_id SET MASK retail.governance.mask_pseudonymous_id;

-- Test 1: you are not in pii_readers, so you should see ***** (owners are not exempt)
SELECT customer_id, COUNT(*) AS rows
FROM retail.bronze.transactions
GROUP BY customer_id
ORDER BY rows DESC
LIMIT 5;

-- Test 2: after joining pii_readers
SELECT is_account_group_member('pii_readers') AS am_i_a_reader;   -- expect true

SELECT customer_id, COUNT(*) AS rows
FROM retail.bronze.transactions
GROUP BY customer_id
ORDER BY rows DESC
LIMIT 5;                                                          -- expect real IDs again

-- Superseded by PII coverage control v2 in 11_governed_value_tags_ABAC.sql (F028).
-- This v1 only reads column_masks, so it now reports customer_id (protected by the ABAC policy) as a false gap.
-- Control: every column tagged pii must have a column mask (expect 0 rows)
select * from retail.information_schema.column_tags;
select * from retail.information_schema.column_masks;

SELECT t.catalog_name, t.schema_name, t.table_name, t.column_name, t.tag_value
FROM retail.information_schema.column_tags t
LEFT ANTI JOIN retail.information_schema.column_masks m
  ON  m.table_catalog = t.catalog_name
  AND m.table_schema  = t.schema_name
  AND m.table_name    = t.table_name
  AND m.column_name   = t.column_name
WHERE t.tag_name = 'pii';

-- Negative test, run once on 2026-11-15. Commented out so a full re-run cannot reapply the tag (see F026).
-- ALTER TABLE retail.bronze.transactions ALTER COLUMN country SET TAGS ('pii' = 'test');

-- rerun the control: expect 1 row, country
-- ALTER TABLE retail.bronze.transactions ALTER COLUMN country UNSET TAGS ('pii');
-- rerun again: back to 0 rows