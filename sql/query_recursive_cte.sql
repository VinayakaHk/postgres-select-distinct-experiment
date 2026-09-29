-- The recursive CTE workaround (recursive_cte.sql from the article).
EXPLAIN (ANALYZE, BUFFERS)
WITH RECURSIVE partitions(pk) AS (
    SELECT min(queue_partition_key) AS pk
    FROM dbos.workflow_status
    WHERE queue_name = 'example_queue'
      AND status = 'ENQUEUED'
      AND queue_partition_key IS NOT NULL

    UNION ALL

    SELECT (
        SELECT min(queue_partition_key)
        FROM dbos.workflow_status
        WHERE queue_name = 'example_queue'
          AND status = 'ENQUEUED'
          AND queue_partition_key > partitions.pk
    )
    FROM partitions
    WHERE partitions.pk IS NOT NULL
)
SELECT pk FROM partitions WHERE pk IS NOT NULL;
