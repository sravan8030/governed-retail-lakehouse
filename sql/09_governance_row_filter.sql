-- 09_governance_row_filter.sql
CREATE TABLE IF NOT EXISTS retail.governance.country_access (
  group_name STRING COMMENT 'Account group granted access',
  country    STRING COMMENT 'Country value the group may see, as stored in the source'
) COMMENT 'Row-level access by country. Read by the row filter retail.governance.filter_country';

ALTER TABLE retail.governance.country_access OWNER TO `retail_data_stewards`;

INSERT INTO retail.governance.country_access VALUES ('retail_data_analysts', 'United Kingdom');

GRANT USE CATALOG, BROWSE ON CATALOG retail TO `retail_data_analysts`;
GRANT USE SCHEMA, SELECT ON SCHEMA retail.gold TO `retail_data_analysts`;
select * from system.information_schema.schema_privileges;
--Verify the grants
SELECT 'catalog:' || catalog_name AS level, privilege_type FROM system.information_schema.catalog_privileges WHERE grantee = 'retail_data_analysts'
UNION ALL
SELECT 'schema:' || schema_name as level, privilege_type FROM system.information_schema.schema_privileges WHERE grantee = 'retail_data_analysts';

-- must be true
-- must be false for test 1
SELECT is_account_group_member('retail_data_analysts') AS analyst,      
  is_account_group_member('retail_all_regions')   AS all_regions;  
  

--REVOKE USE CATALOG, BROWSE ON CATALOG retail FROM `retail_analysts`;
--REVOKE USE SCHEMA, SELECT ON SCHEMA retail.gold FROM `retail_analysts`;


CREATE OR REPLACE FUNCTION retail.governance.filter_country(p_country STRING)
RETURNS BOOLEAN
COMMENT 'Row filter on country. retail_all_regions sees all rows; other groups see only the countries mapped to them in governance.country_access'
RETURN is_account_group_member('retail_all_regions')
    OR EXISTS (SELECT 1 FROM retail.governance.country_access a
        WHERE a.country = p_country AND is_account_group_member(a.group_name));

ALTER FUNCTION retail.governance.filter_country OWNER TO `retail_data_stewards`;

--Function ownership validation
SELECT routine_schema, routine_name, routine_owner, last_altered
FROM retail.information_schema.routines
WHERE routine_schema = 'governance';

--Apply Row filter on the table
ALTER TABLE retail.bronze.transactions SET ROW FILTER retail.governance.filter_country ON (country);

--Row filter on the table validation
SELECT table_schema, table_name, filter_name, target_columns
FROM retail.information_schema.row_filters;

-- How to remove the filter (not part of the build)
--ALTER TABLE retail.bronze.transactions DROP ROW FILTER;

-- Test 1: you are in retail_analysts but not retail_all_regions -> expect only United Kingdom, 981,330 rows
SELECT country, COUNT(*) AS rows
FROM retail.bronze.transactions
GROUP BY country;

-- validate expect true
SELECT is_account_group_member('retail_all_regions') AS all_regions;

-- validate retail_all_regions access across cuontrys, expect 43 and 1,067,371
SELECT COUNT(DISTINCT country) AS countries, COUNT(*) AS rows
FROM retail.bronze.transactions;