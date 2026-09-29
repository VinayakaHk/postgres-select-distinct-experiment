# Postgres `SELECT DISTINCT` Does Not Scale — Experiment

A reproducible experiment demonstrating why Postgres `SELECT DISTINCT` scales with the
total number of rows (not the number of unique values), and how a recursive CTE
workaround fixes it.

Inspired by the DBOS blog post:
<https://www.dbos.dev/blog/postgres-select-distinct-does-not-scale>

## The problem

`SELECT DISTINCT` on an indexed column still performs a **full scan** of every row
matching its predicates, even when there are only a handful of unique values. On a
"narrow but deep" dataset (few partitions, many rows each) this is dramatically slower
than expected.

## Setup

Requires Docker.

```bash
# Start Postgres 18 (note the PG18+ volume mount at /var/lib/postgresql)
docker run -d \
  --name pg \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_DB=postgres \
  -p 5432:5432 \
  -v pgdata:/var/lib/postgresql \
  postgres:18

# Create the experiment database
docker exec pg psql -U postgres -c "CREATE DATABASE distinct_demo;"

# Load schema + data (1M rows across 3 partitions)
docker cp sql/schema.sql    pg:/tmp/schema.sql
docker cp sql/load_data.sql pg:/tmp/load_data.sql
docker exec pg psql -U postgres -d distinct_demo -f /tmp/schema.sql
docker exec pg psql -U postgres -d distinct_demo -f /tmp/load_data.sql
```

Or just run `./run.sh`.

## Run the comparison

```bash
docker cp sql/query_distinct.sql      pg:/tmp/query_distinct.sql
docker cp sql/query_recursive_cte.sql pg:/tmp/query_recursive_cte.sql

# 1) Slow: SELECT DISTINCT (scans all rows)
docker exec pg psql -U postgres -d distinct_demo -f /tmp/query_distinct.sql

# 2) Fast: recursive CTE (one min() lookup per unique partition)
docker exec pg psql -U postgres -d distinct_demo -f /tmp/query_recursive_cte.sql
```

## Results (1M rows, 3 partitions)

| Query          | Plan                                | Rows scanned | Execution time |
|----------------|-------------------------------------|--------------|----------------|
| `SELECT DISTINCT` | Parallel Seq Scan → HashAggregate | 1,000,000    | ~91 ms         |
| Recursive CTE  | Index Only Scan, `min()` per partition | 4 lookups | ~0.2 ms        |

The `SELECT DISTINCT` runtime scales linearly with rows-per-partition, while the
recursive CTE stays flat because each iteration does a single `min()` on the sorted
index.

## Benchmarks

`./benchmark.sh` sweeps rows-per-partition (1K → 1M) with a fixed 10 partitions and
reports median latency for both queries. Results:

| rows/partition | total rows | `SELECT DISTINCT` (ms) | recursive CTE (ms) |
|---------------:|-----------:|-----------------------:|-------------------:|
| 1,000          | 10,000     | 1.5                    | 0.12               |
| 10,000         | 100,000    | 14.8                   | 0.14               |
| 100,000        | 1,000,000  | 54.1                   | 0.19               |
| 1,000,000      | 10,000,000 | 961.1                  | 0.16               |

`SELECT DISTINCT` grows linearly with total rows; the recursive CTE stays flat. See
[`benchmarks/RESULTS.md`](./benchmarks/RESULTS.md) for details and
[`benchmarks/results.csv`](./benchmarks/results.csv) for raw data.

## Files

- `sql/schema.sql` — `dbos.workflow_status` table + partial multicolumn index
- `sql/load_data.sql` — generates 1M rows across 3 partitions
- `sql/query_distinct.sql` — the slow `SELECT DISTINCT` query
- `sql/query_recursive_cte.sql` — the recursive CTE workaround
