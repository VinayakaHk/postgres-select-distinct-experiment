-- Schema for the SELECT DISTINCT experiment, mirroring the DBOS article.
-- Reference: https://www.dbos.dev/blog/postgres-select-distinct-does-not-scale

CREATE SCHEMA IF NOT EXISTS dbos;

DROP TABLE IF EXISTS dbos.workflow_status;

CREATE TABLE dbos.workflow_status (
    workflow_uuid        TEXT PRIMARY KEY,
    queue_name           TEXT,
    status               TEXT,
    queue_partition_key  TEXT
);

-- Partial multicolumn index from the article (index.sql).
-- Note: the article's image showed a trailing comma after queue_partition_key,
-- which is a syntax error in real Postgres, so it is omitted here.
CREATE INDEX idx_workflow_status_partition_dequeue
    ON dbos.workflow_status (
        queue_name,
        status,
        queue_partition_key
    )
    WHERE status IN ('ENQUEUED', 'PENDING')
      AND queue_partition_key IS NOT NULL;
