-- The original SELECT DISTINCT query (find_partitions.sql from the article).
EXPLAIN (ANALYZE, BUFFERS)
SELECT DISTINCT queue_partition_key
FROM dbos.workflow_status
WHERE queue_name = 'example_queue'
  AND status = 'ENQUEUED'
  AND queue_partition_key IS NOT NULL;
