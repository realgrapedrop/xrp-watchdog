#!/bin/bash
# Monitor backfill collection progress

echo "=== XRP Watchdog Backfill Monitor ==="
echo "Timestamp: $(date)"
echo ""

# Check if backfill process is running
BACKFILL_PID=$(cat /tmp/backfill_pid.txt 2>/dev/null)
if [ -n "$BACKFILL_PID" ] && ps -p $BACKFILL_PID > /dev/null 2>&1; then
    echo "✅ Backfill process running (PID: $BACKFILL_PID)"
else
    echo "❌ Backfill process not found"
fi
echo ""

# CPU Load
echo "📊 System Load:"
uptime | awk -F'load average:' '{print "   " $2}'
echo ""

# Database progress
echo "💾 Database Progress:"
docker exec xrp-watchdog-clickhouse clickhouse-client -q "
SELECT
    count(*) as total_trades,
    count(DISTINCT ledger_index) as unique_ledgers,
    max(ledger_index) as latest_ledger,
    formatDateTime(max(time), '%Y-%m-%d %H:%M:%S') as latest_time
FROM xrp_watchdog.executed_trades
FORMAT Vertical" | sed 's/^/   /'
echo ""

# Backfill range progress
echo "🔄 Backfill Range (99949435-99953988):"
docker exec xrp-watchdog-clickhouse clickhouse-client -q "
SELECT
    count(DISTINCT ledger_index) as collected,
    4554 as total_needed,
    round(count(DISTINCT ledger_index) / 4554.0 * 100, 1) as percent_complete,
    4554 - count(DISTINCT ledger_index) as remaining
FROM xrp_watchdog.executed_trades
WHERE ledger_index >= 99949435 AND ledger_index <= 99953988
FORMAT Vertical" | sed 's/^/   /'
echo ""

# Recent log output
echo "📝 Recent Log Output:"
tail -15 /tmp/backfill_collection.log 2>/dev/null | sed 's/^/   /' || echo "   (No log file yet)"
