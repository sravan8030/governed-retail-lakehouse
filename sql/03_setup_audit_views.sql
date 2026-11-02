show tables in retail.dq;
drop table retail.dq.audit_human;
-- 1. Human activity only
CREATE OR REPLACE VIEW retail.dq.audit_users AS
SELECT * FROM system.access.audit
WHERE user_identity.email LIKE '%@%';

select count(*) FROM retail.dq.audit_users;

-- 2. Activity on this project only
CREATE OR REPLACE VIEW retail.dq.audit_retail AS
SELECT * FROM system.access.audit
WHERE request_params.full_name_arg LIKE 'retail.%'
   OR request_params.securable_full_name LIKE 'retail%'
   OR request_params.catalog_name = 'retail';

select count(*) FROM retail.dq.audit_retail;

-- 3. Privileged changes, whoever made them
CREATE OR REPLACE VIEW retail.dq.audit_privileged_changes AS
SELECT * FROM system.access.audit
WHERE action_name ILIKE ANY ('update%', 'create%', 'delete%', 'batch%')
   OR action_name ILIKE '%permission%';

select count(*) FROM retail.dq.audit_privileged_changes;

show tables in retail.dq;

SELECT table_name, table_type, comment
FROM retail.information_schema.tables
WHERE table_schema = 'dq';

COMMENT ON VIEW retail.dq.audit_users IS 'Audit events by human identities only; excludes service principals and System-User';
COMMENT ON VIEW retail.dq.audit_retail IS 'Audit events touching objects in the retail catalog; refine filter as new event types appear';
COMMENT ON VIEW retail.dq.audit_privileged_changes IS 'Create, update, delete and permission events by any identity; basis for privileged-activity review';

SELECT 'users' AS view_name, COUNT(*) AS events FROM retail.dq.audit_users
UNION ALL SELECT 'retail', COUNT(*) FROM retail.dq.audit_retail
UNION ALL SELECT 'privileged', COUNT(*) FROM retail.dq.audit_privileged_changes;
describe table extended retail.dq.audit_users;
describe table extended retail.dq.audit_retail;
describe table extended retail.dq.audit_privileged_changes;k