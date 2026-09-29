#!/usr/bin/env bash
# Benchmark: sweep rows-per-partition and measure query latency for
# SELECT DISTINCT vs the recursive CTE workaround.
#
# Fixes the number of partitions (default 10) and varies rows-per-partition
# across 1K, 10K, 100K, 1M, 10M. For each scale it runs each query REPS times
# and reports the median EXPLAIN ANALYZE execution time (ms).
set -euo pipefail

CONTAINER="${CONTAINER:-pg}"
DB="${DB:-distinct_bench}"
PARTITIONS="${PARTITIONS:-10}"
REPS="${REPS:-5}"
# Note: 10M rows/partition (100M total) is impractically slow to generate and
# query on a laptop; the trend is already conclusive by 1M. Add 10000000 back
# if you want to push further.
SCALES=(1000 10000 100000 1000000)

psql_db() { docker exec -i "$CONTAINER" psql -U postgres -d "$DB" -qtAX "$@"; }

echo "==> (Re)creating database '$DB'"
docker exec "$CONTAINER" psql -U postgres -c "DROP DATABASE IF EXISTS $DB;" >/dev/null
docker exec "$CONTAINER" psql -U postgres -c "CREATE DATABASE $DB;" >/dev/null

echo "==> Creating schema + index"
psql_db >/dev/null <<'SQL'
CREATE SCHEMA IF NOT EXISTS dbos;
CREATE TABLE dbos.workflow_status (
    workflow_uuid        TEXT PRIMARY KEY,
    queue_name           TEXT,
    status               TEXT,
    queue_partition_key  TEXT
);
CREATE INDEX idx_workflow_status_partition_dequeue
    ON dbos.workflow_status (queue_name, status, queue_partition_key)
    WHERE status IN ('ENQUEUED', 'PENDING')
      AND queue_partition_key IS NOT NULL;
SQL

# Query definitions (wrapped in EXPLAIN ANALYZE, extract Execution Time line).
DISTINCT_SQL="EXPLAIN (ANALYZE, TIMING OFF, SUMMARY ON)
SELECT DISTINCT queue_partition_key
FROM dbos.workflow_status
WHERE queue_name = 'example_queue' AND status = 'ENQUEUED' AND queue_partition_key IS NOT NULL;"

CTE_SQL="EXPLAIN (ANALYZE, TIMING OFF, SUMMARY ON)
WITH RECURSIVE partitions(pk) AS (
    SELECT min(queue_partition_key) AS pk FROM dbos.workflow_status
    WHERE queue_name = 'example_queue' AND status = 'ENQUEUED' AND queue_partition_key IS NOT NULL
    UNION ALL
    SELECT (SELECT min(queue_partition_key) FROM dbos.workflow_status
            WHERE queue_name = 'example_queue' AND status = 'ENQUEUED' AND queue_partition_key > partitions.pk)
    FROM partitions WHERE partitions.pk IS NOT NULL
) SELECT pk FROM partitions WHERE pk IS NOT NULL;"

# Median of the "Execution Time: N ms" line over REPS runs.
median_exec_ms() {
  local sql="$1" reps="$2"
  local times=()
  for _ in $(seq 1 "$reps"); do
    local t
    t=$(printf '%s\n' "$sql" | psql_db | grep -i 'Execution Time' | grep -Eo '[0-9]+\.[0-9]+' | head -1)
    times+=("$t")
  done
  printf '%s\n' "${times[@]}" | sort -n | awk '{a[NR]=$1} END{print (NR%2)? a[(NR+1)/2] : (a[NR/2]+a[NR/2+1])/2}'
}

printf "\n%-12s %-14s %-18s %-18s\n" "rows/part" "total_rows" "DISTINCT (ms)" "recursiveCTE (ms)"
printf "%-12s %-14s %-18s %-18s\n" "---------" "----------" "-------------" "-----------------"

RESULTS_CSV="benchmarks/results.csv"
mkdir -p benchmarks
echo "rows_per_partition,total_rows,partitions,distinct_ms,recursive_cte_ms" > "$RESULTS_CSV"

for rpp in "${SCALES[@]}"; do
  total=$(( rpp * PARTITIONS ))
  # Reload data at this scale. queue_partition_key cycles across PARTITIONS values.
  psql_db >/dev/null <<SQL
TRUNCATE dbos.workflow_status;
INSERT INTO dbos.workflow_status (workflow_uuid, queue_name, status, queue_partition_key)
SELECT 'wf_' || g, 'example_queue', 'ENQUEUED',
       'tenant_' || lpad((g % ${PARTITIONS})::text, 3, '0')
FROM generate_series(1, ${total}) AS g;
ANALYZE dbos.workflow_status;
SQL

  d_ms=$(median_exec_ms "$DISTINCT_SQL" "$REPS")
  c_ms=$(median_exec_ms "$CTE_SQL" "$REPS")

  printf "%-12s %-14s %-18s %-18s\n" "$rpp" "$total" "$d_ms" "$c_ms"
  echo "${rpp},${total},${PARTITIONS},${d_ms},${c_ms}" >> "$RESULTS_CSV"
done

echo ""
echo "==> Results written to $RESULTS_CSV"
