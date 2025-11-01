# Storage Management Guide

## Overview

XRP Watchdog uses ClickHouse for efficient storage of wash trading data. The system has built-in TTL (Time To Live) policies to automatically manage data retention and prevent unbounded growth.

## Current Configuration

### Data Retention Policies

| Table | TTL Policy | Purpose |
|-------|------------|---------|
| `executed_trades` | 90 days | Raw trade data from DEX transactions |
| `book_changes` | 90 days | Order book changes and depth snapshots |
| `token_stats` | Indefinite | Aggregated risk metrics (updated in-place) |
| `token_whitelist` | Indefinite | Known legitimate tokens |
| `collection_state` | Indefinite | Collector state tracking |

### Storage Projections

Based on current collection rates (~1.24 MiB/day):

| Period | Projected Size | Projected Rows | Notes |
|--------|----------------|----------------|-------|
| 30 days | ~37 MiB | ~482K rows | Early growth phase |
| **90 days (Steady State)** | **~111 MiB** | **~1.4M rows** | **Max size with TTL** |
| 6 months | ~222 MiB | ~2.9M rows | If TTL removed |
| 1 year | ~451 MiB | ~5.9M rows | If TTL removed |

**Key Insight**: With 90-day TTL enabled, the database will stabilize at approximately **111 MiB** (~0.1 GiB) after 90 days of operation. This is extremely manageable and requires no active maintenance.

## Growth Analysis

### Current Metrics (as of 2025-11-01)

- **Days Collected**: 13 days
- **Current Size**: 16.07 MiB
- **Total Rows**: 209,100
- **Growth Rate**: 1.24 MiB/day
- **Avg Trades/Day**: 3,787

### Breakdown by Table

| Table | Size | Rows | Growth Rate |
|-------|------|------|-------------|
| `book_changes` | 8.98 MiB | 159,696 | ~0.69 MiB/day |
| `executed_trades` | 7.06 MiB | 49,228 | ~0.54 MiB/day |
| `token_stats` | 28.36 KiB | 169 | Minimal (refreshed) |

### Time to Milestones

- **Steady State (90 days)**: 77 days remaining → ~111 MiB
- **1 GiB**: ~831 days (27.7 months) *if TTL were disabled*
- **10 GiB**: Never reached due to TTL policy

## Monitoring Storage

### Manual Check

Run the storage monitoring script:

```bash
cd /home/grapedrop/monitoring/xrp-watchdog
source venv/bin/activate
python scripts/check_storage.py
```

Output includes:
- Current database size by table
- Data collection period and growth rate
- Storage projections for various time periods
- TTL policy status
- Recommendations

### Query ClickHouse Directly

```sql
-- Check database size
SELECT
    table,
    formatReadableSize(sum(bytes)) as size,
    sum(rows) as rows
FROM system.parts
WHERE database = 'xrp_watchdog'
  AND active = 1
GROUP BY table
ORDER BY sum(bytes) DESC;

-- Check oldest data (should be ~90 days old at steady state)
SELECT MIN(time), MAX(time) FROM executed_trades;

-- Check TTL execution
SELECT * FROM system.parts_log
WHERE database = 'xrp_watchdog'
  AND event_type = 'RemovePart'
ORDER BY event_time DESC
LIMIT 10;
```

### Grafana Dashboard

Add a storage monitoring panel to your Grafana dashboard:

```sql
SELECT
    formatReadableSize(sum(bytes)) as "Database Size",
    sum(rows) as "Total Rows"
FROM system.parts
WHERE database = 'xrp_watchdog'
  AND active = 1
```

## Maintenance Tasks

### Monthly Optimization (Optional)

ClickHouse automatically merges parts and removes expired data, but you can manually optimize for best performance:

```bash
# Optimize all tables
clickhouse-client --query "OPTIMIZE TABLE xrp_watchdog.executed_trades FINAL"
clickhouse-client --query "OPTIMIZE TABLE xrp_watchdog.book_changes FINAL"
clickhouse-client --query "OPTIMIZE TABLE xrp_watchdog.token_stats FINAL"
```

**When to run**: Monthly, during low-activity periods

**Expected duration**: 1-5 seconds for current data sizes

### Check Disk Space

```bash
# Check ClickHouse data directory size
du -sh /var/lib/clickhouse/

# Check available disk space
df -h /var/lib/clickhouse
```

## Adjusting TTL Policies

### Extend Retention to 180 Days

If you need longer historical data:

```sql
ALTER TABLE xrp_watchdog.executed_trades
MODIFY TTL toDateTime(time) + toIntervalDay(180);

ALTER TABLE xrp_watchdog.book_changes
MODIFY TTL toDateTime(time) + toIntervalDay(180);
```

**Impact**: Steady state size would double to ~222 MiB

### Remove TTL (Indefinite Retention)

```sql
ALTER TABLE xrp_watchdog.executed_trades
REMOVE TTL;

ALTER TABLE xrp_watchdog.book_changes
REMOVE TTL;
```

**Impact**:
- 1 year: ~451 MiB
- 2 years: ~900 MiB
- Linear growth at ~1.24 MiB/day

### Shorten Retention to 30 Days

For minimal storage:

```sql
ALTER TABLE xrp_watchdog.executed_trades
MODIFY TTL toDateTime(time) + toIntervalDay(30);

ALTER TABLE xrp_watchdog.book_changes
MODIFY TTL toDateTime(time) + toIntervalDay(30);
```

**Impact**: Steady state size would reduce to ~37 MiB

## Backup Strategy

### Export Data to Parquet

For long-term archival:

```sql
-- Export executed_trades
SELECT * FROM xrp_watchdog.executed_trades
INTO OUTFILE '/tmp/executed_trades_archive.parquet'
FORMAT Parquet;

-- Export token_stats
SELECT * FROM xrp_watchdog.token_stats
INTO OUTFILE '/tmp/token_stats_archive.parquet'
FORMAT Parquet;
```

### Automated Monthly Backups

Create a backup script in cron:

```bash
#!/bin/bash
BACKUP_DIR="/home/grapedrop/monitoring/xrp-watchdog/backups"
DATE=$(date +%Y%m%d)

mkdir -p $BACKUP_DIR

# Backup token_stats (small, keep indefinitely)
clickhouse-client --query "SELECT * FROM xrp_watchdog.token_stats FORMAT CSVWithNames" > $BACKUP_DIR/token_stats_$DATE.csv

# Keep only last 6 months of backups
find $BACKUP_DIR -name "token_stats_*.csv" -mtime +180 -delete
```

## Performance Considerations

### Current Performance

With 90-day TTL and ~111 MiB steady state:
- **Query Speed**: <100ms for dashboard queries
- **Analysis Speed**: ~40ms for 360+ tokens
- **Collection Speed**: ~10-15 seconds per 5-minute cycle

### Scalability

The system can comfortably handle:
- **10x traffic**: ~1 GiB steady state, still very fast
- **100x traffic**: ~10 GiB steady state, may need partitioning
- **1000x traffic**: Consider partitioning by date or token

## Troubleshooting

### Database Growing Beyond Expected Size

1. Check TTL is working:
   ```sql
   SELECT * FROM system.parts_log
   WHERE database = 'xrp_watchdog'
   ORDER BY event_time DESC
   LIMIT 100;
   ```

2. Check oldest data:
   ```sql
   SELECT MIN(time) FROM executed_trades;
   ```
   Should be ~90 days ago at steady state.

3. Manually trigger TTL:
   ```sql
   OPTIMIZE TABLE executed_trades FINAL;
   ```

### Need to Reclaim Space Immediately

```sql
-- Drop old partitions manually
ALTER TABLE executed_trades
DROP PARTITION ID '<partition_id>';
```

## Best Practices

1. **Monitor Weekly**: Run `scripts/check_storage.py` weekly to track growth
2. **Optimize Monthly**: Run `OPTIMIZE TABLE FINAL` once a month
3. **Check TTL**: Verify TTL is executing by checking oldest data dates
4. **Backup Important Data**: Periodically export `token_stats` for long-term analysis
5. **Adjust TTL as Needed**: 90 days is optimal for most use cases, but adjust based on needs

## Conclusion

XRP Watchdog's storage management is **extremely efficient**:
- ✅ Steady state at ~111 MiB (0.1 GiB)
- ✅ Automatic cleanup via TTL
- ✅ No manual intervention required
- ✅ Scalable to 10x-100x current traffic

The system is designed for minimal operational overhead while maintaining comprehensive wash trading detection capabilities.
