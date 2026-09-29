#!/usr/bin/env bash
# One-shot setup + comparison for the SELECT DISTINCT experiment.
set -euo pipefail

CONTAINER="${CONTAINER:-pg}"
DB="${DB:-distinct_demo}"

echo "==> Ensuring database '$DB' exists"
docker exec "$CONTAINER" psql -U postgres -tc \
  "SELECT 1 FROM pg_database WHERE datname = '$DB'" | grep -q 1 || \
  docker exec "$CONTAINER" psql -U postgres -c "CREATE DATABASE $DB;"

echo "==> Copying SQL into container"
for f in schema load_data query_distinct query_recursive_cte; do
  docker cp "sql/${f}.sql" "$CONTAINER:/tmp/${f}.sql"
done

echo "==> Applying schema"
docker exec "$CONTAINER" psql -U postgres -d "$DB" -f /tmp/schema.sql

echo "==> Loading data (1M rows)"
docker exec "$CONTAINER" psql -U postgres -d "$DB" -f /tmp/load_data.sql

echo ""
echo "############################################"
echo "### 1) SLOW: SELECT DISTINCT (full scan) ###"
echo "############################################"
docker exec "$CONTAINER" psql -U postgres -d "$DB" -f /tmp/query_distinct.sql

echo ""
echo "####################################################"
echo "### 2) FAST: Recursive CTE (min() per partition) ###"
echo "####################################################"
docker exec "$CONTAINER" psql -U postgres -d "$DB" -f /tmp/query_recursive_cte.sql
