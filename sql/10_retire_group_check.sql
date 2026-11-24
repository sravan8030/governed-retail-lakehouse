--10_retire_group_check

--REVOKE USE CATALOG, BROWSE ON CATALOG retail FROM `retail_analysts`;
--REVOKE USE SCHEMA, SELECT ON SCHEMA retail.gold FROM `retail_analysts`;

--select * from retail.governance.country_access;
--delete from retail.governance.country_access where group_name != 'retail_data_analysts';

--verify the grans the group_name holds;
SELECT 'catalog' AS level, catalog_name AS object_name, privilege_type
FROM system.information_schema.catalog_privileges WHERE grantee = 'retail_analysts'
UNION ALL
SELECT 'schema', catalog_name || '.' || schema_name, privilege_type
FROM system.information_schema.schema_privileges WHERE grantee = 'retail_analysts'
UNION ALL
SELECT 'table', table_catalog || '.' || table_schema || '.' || table_name, privilege_type
FROM system.information_schema.table_privileges WHERE grantee = 'retail_analysts'
UNION ALL
SELECT 'volume', volume_catalog || '.' || volume_schema || '.' || volume_name, privilege_type
FROM system.information_schema.volume_privileges WHERE grantee = 'retail_analysts'
UNION ALL
SELECT 'function', routine_catalog || '.' || routine_schema || '.' || routine_name, privilege_type
FROM system.information_schema.routine_privileges WHERE grantee = 'retail_analysts';


SELECT 'catalog' AS level, catalog_name AS object_name FROM system.information_schema.catalogs WHERE catalog_owner = 'retail_analysts'
UNION ALL
SELECT 'schema', catalog_name || '.' || schema_name FROM system.information_schema.schemata WHERE schema_owner = 'retail_analysts'
UNION ALL
SELECT 'table', table_catalog || '.' || table_schema || '.' || table_name FROM system.information_schema.tables WHERE table_owner = 'retail_analysts'
UNION ALL
SELECT 'volume', volume_catalog || '.' || volume_schema || '.' || volume_name FROM system.information_schema.volumes WHERE volume_owner = 'retail_analysts'
UNION ALL
SELECT 'function', routine_catalog || '.' || routine_schema || '.' || routine_name FROM system.information_schema.routines WHERE routine_owner = 'retail_analysts';


SELECT 'country_access' AS source, group_name FROM retail.governance.country_access WHERE group_name = 'retail_analysts'
UNION ALL
SELECT 'control_exceptions', approved_by FROM retail.dq.control_exceptions WHERE approved_by = 'retail_analysts'
UNION ALL
SELECT 'tag_vocabulary', tag_value FROM retail.governance.tag_vocabulary WHERE tag_value = 'retail_analysts';
