-- 00_setup.sql
-- Creates the project catalog and medallion schemas, each with a stated purpose.

CREATE CATALOG IF NOT EXISTS retail;
COMMENT ON CATALOG retail IS 'Governed retail lakehouse: learning build on Online Retail II (UCI)';

CREATE SCHEMA IF NOT EXISTS retail.bronze COMMENT 'Raw data exactly as received; no changes, load metadata added';
CREATE SCHEMA IF NOT EXISTS retail.silver COMMENT 'Validated and conformed data; only rows that pass DQ rules';
CREATE SCHEMA IF NOT EXISTS retail.gold   COMMENT 'Certified, business-ready aggregates for reporting';
CREATE SCHEMA IF NOT EXISTS retail.dq     COMMENT 'Data quality artefacts: quarantine, rule results, monitor metrics, incidents';

-- D001: remove the auto-created default schema
DROP SCHEMA IF EXISTS retail.default;

-- Evidence: every schema has a description
SELECT schema_name, comment
FROM retail.information_schema.schemata
ORDER BY schema_name;

-- Next (Week 1, Tuesday): landing volume for raw source files
-- CREATE VOLUME IF NOT EXISTS retail.bronze.landing
--   COMMENT 'Raw source files as received, before loading to Bronze tables';
