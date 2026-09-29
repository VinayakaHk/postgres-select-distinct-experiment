# Benchmark Results

Fixed **10 partitions**, varying **rows-per-partition**. Median `EXPLAIN ANALYZE`
execution time over 5 runs each.

| rows/partition | total rows | `SELECT DISTINCT` (ms) | recursive CTE (ms) | speedup |
|---------------:|-----------:|-----------------------:|-------------------:|--------:|
| 1,000          | 10,000     | 1.520                  | 0.123              | ~12×    |
| 10,000         | 100,000    | 14.833                 | 0.144              | ~103×   |
| 100,000        | 1,000,000  | 54.133                 | 0.192              | ~282×   |
| 1,000,000      | 10,000,000 | 961.053                | 0.156              | ~6162×  |

## Takeaway

- **`SELECT DISTINCT` scales linearly with the total number of rows.** From 10K to 10M
  total rows (1000×), latency grew from ~1.5 ms to ~961 ms (~630×) — it scans every
  matching row.
- **The recursive CTE stays flat**, holding ~0.12–0.19 ms regardless of table size,
  because each iteration does a single `min()` lookup on the sorted index. Its cost is
  O(number of unique partitions), not O(rows).
- The speedup widens dramatically as data grows: ~12× at 10K rows to ~6000× at 10M rows.

## Notes

- 10M rows/partition (100M total) was excluded: data generation and the full-scan
  `SELECT DISTINCT` become impractically slow on a laptop, and the linear trend is
  already conclusive by 1M rows/partition. Add `10000000` to `SCALES` in
  `benchmark.sh` to push further.
- Reproduce with `./benchmark.sh` (env vars: `PARTITIONS`, `REPS`, `DB`, `CONTAINER`).
- Raw data in [`results.csv`](./results.csv).
