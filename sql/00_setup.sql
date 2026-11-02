-- 00_setup.sql
-- Creates the project catalog and medallion schemas, each with a stated purpose.

create catalog if not exists retail;
show catalogs;

comment on catalog retail is 'Governed retail lakehouse: learning build on Online Retail II (UCI)';
create schema if not exists retail.bronze comment 'Raw data exactly as received; no changes, load metadata added';
create schema if not exists retail.silver comment'Validated and conformed data; only rows that pass DQ rules';
create schema if not exists retail.gold comment 'Certified, business-ready aggregates for reporting';
create schema if not exists retail.dq comment 'Data quality artefacts: quarantine, rule results, monitor metrics, incidents';

show schemas in retail;

describe catalog extended retail;       
describe schema extended retail.bronze;
describe schema extended retail.silver;
describe schema extended retail.gold;

select schema_name, comment 
from retail.information_schema.schemata
order by schema_name;

drop schema if exists retail.default;

-- Next (Week 1, Tuesday): landing volume for raw source files
-- CREATE VOLUME IF NOT EXISTS retail.bronze.landing
--   COMMENT 'Raw source files as received, before loading to Bronze tables';
