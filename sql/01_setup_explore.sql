show catalogs;
show schemas in retail ;
show tables in retail.information_schema;
select * 
from retail.information_schema.schemata
order by schema_name;

SELECT event_time, user_identity.email, action_name, request_params
FROM system.access.audit
WHERE service_name = 'unityCatalog'
  AND action_name ILIKE '%function%'
ORDER BY event_time DESC;

SELECT DISTINCT user_identity, identity_metadata
FROM system.access.audit
WHERE event_time > current_date() - INTERVAL 1 DAY;

SELECT user_identity.email AS identity,
       service_name,
       COUNT(*)            AS events,
       MIN(event_time)     AS first_seen,
       MAX(event_time)     AS last_seen
FROM system.access.audit
GROUP BY user_identity.email, service_name
ORDER BY identity, events DESC;

SELECT user_identity.email AS identity, service_name, action_name, COUNT(*) AS events
FROM system.access.audit
WHERE user_identity.email NOT IN ('sravan8030@gmail.com', 'System-User')
GROUP BY ALL
ORDER BY identity, events DESC;

SELECT event_time, user_identity.email AS identity, action_name,
       identity_metadata.run_by, identity_metadata.run_as, request_params
FROM system.access.audit
WHERE user_identity.email NOT IN ('sravan8030@gmail.com', 'System-User')
  AND (action_name ILIKE 'update%' OR action_name ILIKE 'create%'
       OR action_name ILIKE 'delete%' OR action_name ILIKE 'batch%')
ORDER BY event_time;