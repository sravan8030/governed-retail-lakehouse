-- 08_governance_tag_controls.sql
show schemas in retail;
show tables in retail.governance;
show tables in retail.bronze;

CREATE TABLE IF NOT EXISTS retail.governance.tag_vocabulary (
  tag_key   STRING COMMENT 'Allowed tag key',
  tag_value STRING COMMENT 'Allowed value for that key',
  meaning   STRING COMMENT 'What the tag means, as in docs/definitions.md section 5'
) COMMENT 'Approved classification tags. A tag not listed here is an exception (definitions.md rule 3)';

INSERT INTO retail.governance.tag_vocabulary VALUES
 ('cde', 'true', 'Critical data element'),
 ('pii', 'direct_id', 'Identifies a person on its own'),
 ('pii', 'pseudonymous_id', 'Identifies a person only through a lookup'),
 ('pii', 'quasi_id', 'Could identify someone in combination with other columns'),
 ('data_owner', 'retail_data_owners', 'Group accountable for the data'),
 ('data_steward', 'retail_data_stewards', 'Group responsible for definitions, rules and quality');

select * from retail.governance.tag_vocabulary;

-- Control CTL_TAG_VOCABULARY: every tag in use is approved (target: 0 rows)
WITH tags_in_use AS (
  SELECT 'catalog' AS level, catalog_name AS object_name, tag_name, tag_value
  FROM retail.information_schema.catalog_tags
  UNION ALL
  SELECT 'schema', schema_name, tag_name, tag_value
  FROM retail.information_schema.schema_tags
  UNION ALL
  SELECT 'table', schema_name || '.' || table_name, tag_name, tag_value
  FROM retail.information_schema.table_tags
  UNION ALL
  SELECT 'column', schema_name || '.' || table_name || '.' || column_name, tag_name, tag_value
  FROM retail.information_schema.column_tags
)
SELECT u.*
FROM tags_in_use u
LEFT ANTI JOIN retail.governance.tag_vocabulary v
  ON v.tag_key = u.tag_name AND v.tag_value = u.tag_value;

select * from retail.bronze.transactions limit 5;

-- 1. Confirm the PII mask control is currently failing (expect 1 row: country)
SELECT t.catalog_name, t.schema_name, t.table_name, t.column_name, t.tag_value
FROM retail.information_schema.column_tags t
LEFT ANTI JOIN retail.information_schema.column_masks m
  ON  m.table_catalog = t.catalog_name AND m.table_schema = t.schema_name
  AND m.table_name    = t.table_name   AND m.column_name  = t.column_name
WHERE t.tag_name = 'pii';

-- 2. Remove the leftover tag
--ALTER TABLE retail.bronze.transactions ALTER COLUMN country UNSET TAGS ('pii');

-- 3. Rerun both controls: expect 0 rows each