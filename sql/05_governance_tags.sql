
-- 05_governance_tags.sql
-- Classification from docs/definitions.md applied as column tags

-- Critical data elements
ALTER TABLE retail.bronze.transactions ALTER COLUMN invoice      SET TAGS ('cde' = 'true');
ALTER TABLE retail.bronze.transactions ALTER COLUMN stock_code   SET TAGS ('cde' = 'true');
ALTER TABLE retail.bronze.transactions ALTER COLUMN quantity     SET TAGS ('cde' = 'true');
ALTER TABLE retail.bronze.transactions ALTER COLUMN price        SET TAGS ('cde' = 'true');
ALTER TABLE retail.bronze.transactions ALTER COLUMN invoice_date SET TAGS ('cde' = 'true');
ALTER TABLE retail.bronze.transactions ALTER COLUMN customer_id  SET TAGS ('cde' = 'true', 'pii' = 'pseudonymous_id');
ALTER TABLE retail.bronze.transactions ALTER COLUMN country      SET TAGS ('cde' = 'true');

-- Check: which columns carry which tags
SELECT column_name, tag_name, tag_value
FROM retail.information_schema.column_tags
WHERE schema_name = 'bronze' AND table_name = 'transactions'
ORDER BY column_name, tag_name;