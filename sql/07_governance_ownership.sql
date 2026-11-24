SELECT is_account_group_member('retail_data_owners')    AS owners,
       is_account_group_member('retail_data_stewards')  AS stewards,
       is_account_group_member('retail_data_engineers') AS engineers,
       is_account_group_member('retail_analysts')       AS analysts;

-- Control: no object owned by an individual person (target: 0 rows)
SELECT 'schema' AS object_type, schema_name AS object_name, schema_owner AS owner
FROM retail.information_schema.schemata
where schema_owner like '%@%'
--WHERE schema_owner != 'System user'
UNION ALL
SELECT 'table/view', table_schema || '.' || table_name, table_owner
FROM retail.information_schema.tables
--where table_owner !='System user';
WHERE table_owner LIKE '%@%';

drop table retail.bronze.test;

ALTER CATALOG retail            OWNER TO `retail_data_engineers`;
ALTER SCHEMA  retail.bronze     OWNER TO `retail_data_engineers`;
ALTER SCHEMA  retail.silver     OWNER TO `retail_data_engineers`;
ALTER SCHEMA  retail.gold       OWNER TO `retail_data_engineers`;
ALTER SCHEMA  retail.dq         OWNER TO `retail_data_stewards`;
ALTER SCHEMA  retail.governance OWNER TO `retail_data_stewards`;

ALTER TABLE    retail.bronze.transactions              OWNER TO `retail_data_engineers`;
ALTER VOLUME   retail.bronze.landing                   OWNER TO `retail_data_engineers`;
ALTER VIEW     retail.dq.audit_users                   OWNER TO `retail_data_stewards`;
ALTER VIEW     retail.dq.audit_retail                  OWNER TO `retail_data_stewards`;
ALTER VIEW     retail.dq.audit_privileged_changes      OWNER TO `retail_data_stewards`;
ALTER FUNCTION retail.governance.mask_pseudonymous_id  OWNER TO `retail_data_stewards`;

-- Check: views read their source tables with the OWNER's rights, so test straight away
SELECT COUNT(*) FROM retail.dq.audit_users;

--give the stewards group read access to the audit table.
GRANT USE CATALOG ON CATALOG system             TO `retail_data_stewards`;
GRANT USE SCHEMA  ON SCHEMA  system.access      TO `retail_data_stewards`;
GRANT SELECT      ON TABLE   system.access.audit TO `retail_data_stewards`;

--Give the three audit views back to your user, so they work again
ALTER VIEW retail.dq.audit_users              OWNER TO `sravan8030@gmail.com`;
ALTER VIEW retail.dq.audit_retail             OWNER TO `sravan8030@gmail.com`;
ALTER VIEW retail.dq.audit_privileged_changes OWNER TO `sravan8030@gmail.com`;

SELECT COUNT(*) FROM retail.dq.audit_users;   -- should work again

--Record the exceptions in a table, not just in a document.
CREATE TABLE IF NOT EXISTS retail.dq.control_exceptions (
  control_id    STRING COMMENT 'Control the exception applies to',
  object_name   STRING COMMENT 'Fully qualified object excepted from the control',
  reason        STRING COMMENT 'Why the exception is needed',
  approved_by   STRING COMMENT 'Group accountable for the exception',
  approved_on   DATE,
  review_by     DATE   COMMENT 'Date the exception must be re-reviewed'
) COMMENT 'Documented exceptions to governance controls. Every row needs a reason and a review date';

ALTER TABLE retail.dq.control_exceptions OWNER TO `retail_data_stewards`;

INSERT INTO retail.dq.control_exceptions VALUES
 ('CTL_OWNERSHIP_NO_PERSON', 'dq.audit_users',              'View reads system.access.audit; Free Edition does not allow granting system tables to a group (no MANAGE on catalog system)', 'retail_data_stewards', current_date(), date_add(current_date(), 90)),
 ('CTL_OWNERSHIP_NO_PERSON', 'dq.audit_retail',             'Same as dq.audit_users', 'retail_data_stewards', current_date(), date_add(current_date(), 90)),
 ('CTL_OWNERSHIP_NO_PERSON', 'dq.audit_privileged_changes', 'Same as dq.audit_users', 'retail_data_stewards', current_date(), date_add(current_date(), 90));

 -- Control CTL_OWNERSHIP_NO_PERSON: no object owned by a person, except approved exceptions (target: 0 rows)
WITH person_owned AS (
  SELECT 'schema' AS object_type, schema_name AS object_name, schema_owner AS owner
  FROM retail.information_schema.schemata
  WHERE schema_owner LIKE '%@%'
  UNION ALL
  SELECT 'table/view', table_schema || '.' || table_name, table_owner
  FROM retail.information_schema.tables
  WHERE table_owner LIKE '%@%'
)
SELECT p.*
FROM person_owned p
LEFT ANTI JOIN retail.dq.control_exceptions e
  ON  e.control_id  = 'CTL_OWNERSHIP_NO_PERSON'
  AND e.object_name = p.object_name;

--Step 4: business ownership tags.
ALTER CATALOG retail SET TAGS ('data_owner' = 'retail_data_owners', 'data_steward' = 'retail_data_stewards');

SELECT tag_name, tag_value
FROM retail.information_schema.catalog_tags
WHERE catalog_name = 'retail';

--Step 5: grants.
GRANT USE CATALOG, BROWSE ON CATALOG retail TO `retail_data_stewards`;
GRANT USE CATALOG, BROWSE ON CATALOG retail TO `retail_data_owners`;
GRANT USE CATALOG, BROWSE ON CATALOG retail TO `retail_analysts`;

GRANT USE SCHEMA, SELECT ON SCHEMA retail.bronze TO `retail_data_stewards`;
GRANT USE SCHEMA, SELECT ON SCHEMA retail.silver TO `retail_data_stewards`;
GRANT USE SCHEMA, SELECT ON SCHEMA retail.gold   TO `retail_data_stewards`;

GRANT USE SCHEMA, SELECT ON SCHEMA retail.silver TO `retail_data_owners`;
GRANT USE SCHEMA, SELECT ON SCHEMA retail.gold   TO `retail_data_owners`;
GRANT USE SCHEMA, SELECT ON SCHEMA retail.dq     TO `retail_data_owners`;

GRANT USE SCHEMA, SELECT ON SCHEMA retail.gold   TO `retail_analysts`;

GRANT USE SCHEMA, SELECT, MODIFY ON SCHEMA retail.dq TO `retail_data_engineers`;

--Step 6: evidence. Rerun the step 2 control, expecting 0 rows this time, then:
SELECT schema_name, grantee, privilege_type
FROM retail.information_schema.schema_privileges
ORDER BY schema_name, grantee, privilege_type;

SELECT grantee, privilege_type
FROM retail.information_schema.catalog_privileges
ORDER BY grantee, privilege_type;