-- Load "narrow but deep" data: few partitions, many rows each.
-- 3 partitions x ~333,333 ENQUEUED rows = ~1,000,000 rows, matching the article.

TRUNCATE dbos.workflow_status;

INSERT INTO dbos.workflow_status (workflow_uuid, queue_name, status, queue_partition_key)
SELECT
    'wf_' || g::text                     AS workflow_uuid,
    'example_queue'                      AS queue_name,
    'ENQUEUED'                           AS status,
    'tenant_' || (g % 3)::text           AS queue_partition_key  -- tenant_0, tenant_1, tenant_2
FROM generate_series(1, 1000000) AS g;

ANALYZE dbos.workflow_status;
